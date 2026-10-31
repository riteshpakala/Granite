//  WHAT: A channel over two file descriptors: lines of JSON written to one, read from the other. A host's end of
//        a child's stdin and stdout, or the child's own.
//  PIN:  READ WHAT HAS ARRIVED. `read(2)` on the descriptor, never `FileHandle.read(upToCount:)`, which waits for
//        the whole count or the end: a line of a live call would sit unread until the process exited.
//  PIN:  READ OFF MAIN. Lines are read on a thread of the channel's own, so an agent whose run needs the main
//        queue (Granite's engine reduces on main, WebKit draws on it) is never held up by a read.
//  PIN:  A LINE THAT IS NOT A MESSAGE IS DROPPED, and said on `unreadable`: an agent's stdout carries nothing
//        else, so one is a fault to report, not a reason to stop reading.

import Foundation

public final class PipeChannel: AgentChannel, @unchecked Sendable {
    public let messages: AsyncStream<AgentWire>
    private let continuation: AsyncStream<AgentWire>.Continuation
    private let readingDescriptor: Int32
    private let writing: FileHandle
    private let lock = NSLock()
    private var closed = false
    private let unreadable: @Sendable (String) -> Void
    private let owning: Bool
    /// `GRANITE_AGENT_TRACE=1` says every line sent and read on stderr, with the process's pid.
    private static let tracing = ProcessInfo.processInfo.environment["GRANITE_AGENT_TRACE"] == "1"

    static func trace(_ arrow: String, _ line: Data) {
        guard tracing else { return }
        FileHandle.standardError.write(Data("[granite-agent \(getpid())] \(arrow) ".utf8) + line.prefix(300) + Data("\n".utf8))
    }

    /// Reads `reading` from now on; writes to `writing`. With `owning`, the channel closes `writing` on `close()`
    /// and `reading` when it has been read to its end; without, both are left as they are.
    public init(reading: Int32, writing: Int32, owning: Bool = false, unreadable: @escaping @Sendable (String) -> Void = { _ in }) {
        self.readingDescriptor = reading
        self.writing = FileHandle(fileDescriptor: writing, closeOnDealloc: false)
        self.owning = owning
        self.unreadable = unreadable
        (messages, continuation) = AsyncStream.makeStream(of: AgentWire.self)
        let thread = Thread { [continuation, unreadable, owning] in
            var buffer = Data()
            var chunk = [UInt8](repeating: 0, count: 1 << 16)
            while true {
                let count = Darwin.read(reading, &chunk, chunk.count)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { break }
                buffer.append(contentsOf: chunk[0..<count])
                while let end = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<end]
                    buffer = Data(buffer[buffer.index(after: end)...])
                    guard !line.allSatisfy({ $0 == 0x20 || $0 == 0x0D }) else { continue }
                    PipeChannel.trace("read", Data(line))
                    if let message = try? AgentWire.read(Data(line)) {
                        continuation.yield(message)
                    } else {
                        unreadable(String(decoding: line.prefix(200), as: UTF8.self))
                    }
                }
            }
            continuation.finish()
            if owning { Darwin.close(reading) }
        }
        thread.name = "granite.agent.channel"
        thread.start()
    }

    public func send(_ message: AgentWire) throws {
        let line = try message.line()
        PipeChannel.trace("sent", line.dropLast())
        try lock.withLock {
            guard !closed else { throw CocoaError(.fileWriteNoPermission) }
            try writing.write(contentsOf: line)
        }
    }

    public func close() {
        lock.withLock {
            guard !closed else { return }
            closed = true
            if owning { try? writing.close() }
        }
    }

    deinit { close() }
}
