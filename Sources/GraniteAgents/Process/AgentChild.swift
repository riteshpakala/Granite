#if os(macOS)
import Darwin
import Foundation

/// One runner process: spawned with its stdin, stdout and stderr on pipes of the host's, in a process group of
/// its own, read through a `PipeChannel`, and reaped with `wait4` so the call knows what it took.
///
/// PIN: the child starts with no signal blocked. A host spawns from a dispatch worker, whose mask blocks SIGTERM;
/// a child inherits the mask, so without this a cancel could only ever end it with the SIGKILL after the grace.
final class AgentChild: @unchecked Sendable {
    let pid: pid_t
    let channel: PipeChannel
    let started = Date()
    private let lock = NSLock()
    private var stderrTail = Data()
    private var reaped: (status: Int32, usage: rusage)?
    private var waiters: [CheckedContinuation<(status: Int32, usage: rusage), Never>] = []

    init(executable: URL, arguments: [String], directory: URL?, environment: [String: String]) throws {
        var toChild: [Int32] = [0, 0], fromChild: [Int32] = [0, 0], errors: [Int32] = [0, 0]
        guard pipe(&toChild) == 0, pipe(&fromChild) == 0, pipe(&errors) == 0 else {
            throw AgentRemoteError.spawn(path: executable.path, reason: String(cString: strerror(errno)))
        }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, toChild[0], 0)
        posix_spawn_file_actions_adddup2(&actions, fromChild[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errors[1], 2)
        if let directory { posix_spawn_file_actions_addchdir_np(&actions, directory.path) }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var unblocked = sigset_t()
        sigemptyset(&unblocked)
        posix_spawnattr_setsigmask(&attributes, &unblocked)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in [SIGTERM, SIGINT, SIGHUP, SIGQUIT, SIGPIPE] { sigaddset(&defaults, signal) }
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT
                                                     | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))

        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable.path, &actions, &attributes, argv, envp)
        close(toChild[0]); close(fromChild[1]); close(errors[1])
        guard status == 0 else {
            close(toChild[1]); close(fromChild[0]); close(errors[0])
            throw AgentRemoteError.spawn(path: executable.path, reason: String(cString: strerror(status)))
        }
        self.pid = pid
        // The channel owns the host's ends of stdin and stdout from here.
        channel = PipeChannel(reading: fromChild[0], writing: toChild[1], owning: true)

        let errorsRead = errors[0]
        let thread = Thread { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 8192)
            while true {
                let count = read(errorsRead, &buffer, buffer.count)
                if count <= 0 { break }
                self?.keep(Data(buffer[0..<count]))
            }
            close(errorsRead)
        }
        thread.name = "granite.agent.stderr"
        thread.start()

        let child = pid
        let reaper = Thread { [weak self] in
            var raw: Int32 = 0
            var usage = rusage()
            while wait4(child, &raw, 0, &usage) < 0 && errno == EINTR {}
            self?.settle(status: raw, usage: usage)
        }
        reaper.name = "granite.agent.reaper"
        reaper.start()
    }

    deinit { channel.close() }

    /// The end of what the process wrote to stderr, at most a few lines.
    var log: String {
        let text = String(decoding: lock.withLock { stderrTail }, as: UTF8.self)
        return text.split(separator: "\n").suffix(6).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Waits for the process to end; at once when it has.
    func exited() async -> (status: Int32, usage: rusage) {
        await withCheckedContinuation { continuation in
            let done: (status: Int32, usage: rusage)? = lock.withLock {
                if let reaped { return reaped }
                waiters.append(continuation)
                return nil
            }
            if let done { continuation.resume(returning: done) }
        }
    }

    var hasExited: Bool { lock.withLock { reaped != nil } }

    /// SIGTERM to the process's group, then SIGKILL after `grace` if it is still there.
    func terminate(grace: TimeInterval = 2) {
        guard !hasExited else { return }
        kill(-pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + grace) { [weak self] in
            guard let self, !self.hasExited else { return }
            kill(-self.pid, SIGKILL)
        }
    }

    /// What the call took, from the reaped usage.
    func cost(_ ended: (status: Int32, usage: rusage)) -> AgentProcessCost {
        let usage = ended.usage
        let cpu = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        return AgentProcessCost(seconds: Date().timeIntervalSince(started), cpuSeconds: cpu, peakBytes: Int64(usage.ru_maxrss),
                                status: Self.describe(ended.status))
    }

    static func describe(_ raw: Int32) -> String {
        let signal = raw & 0x7f
        return signal == 0 ? "exit \((raw >> 8) & 0xff)" : "signal \(signal)"
    }

    private func keep(_ data: Data) {
        lock.withLock {
            stderrTail.append(data)
            if stderrTail.count > 8192 { stderrTail = stderrTail.suffix(8192) }
        }
    }

    private func settle(status: Int32, usage: rusage) {
        let woken = lock.withLock {
            reaped = (status, usage)
            defer { waiters = [] }
            return waiters
        }
        for waiter in woken { waiter.resume(returning: (status, usage)) }
    }
}
#endif
