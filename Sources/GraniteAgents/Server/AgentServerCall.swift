import Foundation

/// One call a server answers: `hello`, then the host's `perform` started on the roster's package, the host's
/// answers matched to the run's asks, a `cancel` or the host's leaving cancelling it, and exactly one `output`
/// or `failed` said at the end.
final class AgentServerCall: @unchecked Sendable {
    private let channel: any AgentChannel
    private let roster: GraniteRoster
    private let lock = NSLock()
    private var run: Task<Void, Never>?
    private var model: ChannelHostModel?
    private var cancelled = false
    private var done: CheckedContinuation<AgentServer.Exit, Never>?
    private var ended: AgentServer.Exit?

    init(channel: any AgentChannel, roster: GraniteRoster) {
        self.channel = channel
        self.roster = roster
    }

    func serve() async -> AgentServer.Exit {
        try? channel.send(.hello(.init(pid: getpid(), answer: AgentAnswerStandard.format)))
        return await withCheckedContinuation { continuation in
            lock.withLock {
                if let ended { continuation.resume(returning: ended) } else { done = continuation }
            }
            Task { await self.listen() }
        }
    }

    /// Ends the call: the run is cancelled, and says so; before a run, the call ends as cancelled.
    func cancel() {
        let task: Task<Void, Never>? = lock.withLock {
            cancelled = true
            return run
        }
        if let task { task.cancel() } else { finish(.cancelled, .failed("cancelled before the call began")) }
    }

    private func listen() async {
        for await message in channel.messages {
            switch message {
            case .perform(let perform): start(perform)
            case .answer(let answer): lock.withLock { model }?.resolve(answer)
            case .cancel: cancel()
            default: finish(.unreadable, .failed("the host said `\(message.kind)`, which is not a host's message"))
            }
        }
        // The host sends nothing more: a call it made runs on, but no ask of the model can be answered. A host
        // that closes its end at once (`echo '{"perform": …}' | runner`) is served; only `cancel` or SIGTERM
        // cancels. A host that left before calling ends the process.
        lock.withLock { model }?.leave()
        if lock.withLock({ run == nil }) { finish(.unreadable, .failed("the host left before making a call")) }
    }

    private func start(_ perform: AgentWire.Perform) {
        guard lock.withLock({ run == nil && ended == nil }) else {
            return finish(.unreadable, .failed("a process answers one call; the host sent a second `perform`"))
        }
        guard let package = roster.package(perform.word) else {
            let carried = roster.packages.map { "`\($0.word)`" }.joined(separator: ", ")
            return finish(.failed, .failed("no agent is called `\(perform.word)` in this process; it carries \(carried.isEmpty ? "none" : carried)"))
        }
        let model = perform.model ? ChannelHostModel(channel: channel) : nil
        let channel = self.channel
        let host = AgentHost(directory: perform.directory, ask: perform.ask, model: model, note: { line in try? channel.send(.note(line)) })
        let input = perform.input.data()
        let task = Task {
            do {
                let output = try await package.perform(input, host: host)
                guard let json = AgentJSON(data: output) else { return self.finish(.failed, .failed("\(perform.word) answered something that is not JSON")) }
                self.finish(.answered, .output(json))
            } catch is CancellationError {
                self.finish(.cancelled, .failed("cancelled"))
            } catch AgentPackageError.refused(_, let refusal, let said) {
                self.finish(Task.isCancelled ? .cancelled : .refused, .failed(.init(said, refusal: refusal)))
            } catch {
                self.finish(Task.isCancelled ? .cancelled : .failed, .failed("\(error)"))
            }
        }
        let cancelledAlready: Bool = lock.withLock {
            self.model = model
            run = task
            return cancelled
        }
        if cancelledAlready { task.cancel() }
    }

    /// Says `message` and ends the call with `exit`, once.
    private func finish(_ exit: AgentServer.Exit, _ message: AgentWire) {
        let waiting: CheckedContinuation<AgentServer.Exit, Never>?? = lock.withLock {
            guard ended == nil else { return .none }
            ended = exit
            defer { done = nil }
            return .some(done)
        }
        guard case .some(let continuation) = waiting else { return }
        try? channel.send(message)
        continuation?.resume(returning: exit)
    }
}
