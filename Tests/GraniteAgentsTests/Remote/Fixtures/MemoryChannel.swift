import Foundation
import GraniteAgents

/// Two ends of a channel in memory: what one sends, the other hears; closing an end ends the other's stream.
final class MemoryChannel: AgentChannel, @unchecked Sendable {
    let messages: AsyncStream<AgentWire>
    private let inbox: AsyncStream<AgentWire>.Continuation
    private weak var other: MemoryChannel?
    private let lock = NSLock()
    private var closed = false
    private var kept: [AgentWire] = []

    private init() { (messages, inbox) = AsyncStream.makeStream(of: AgentWire.self) }

    static func pair() -> (MemoryChannel, MemoryChannel) {
        let a = MemoryChannel(), b = MemoryChannel()
        a.other = b; b.other = a
        return (a, b)
    }

    /// Everything this end has sent, in order.
    var sent: [AgentWire] { lock.withLock { kept } }

    func send(_ message: AgentWire) throws {
        // Through the wire's own encoding, so what crosses is what a pipe would carry.
        let read = try AgentWire.read(try message.line())
        try lock.withLock {
            guard !closed else { throw CocoaError(.fileWriteNoPermission) }
            kept.append(read)
        }
        other?.inbox.yield(read)
    }

    func close() {
        lock.withLock { closed = true }
        other?.inbox.finish()
    }
}
