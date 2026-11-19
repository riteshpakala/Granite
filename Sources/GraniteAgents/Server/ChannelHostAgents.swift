import Foundation

/// The host's agents, as an agent in another process calls them: each call an `agent` message under an id, each answer
/// the host's `called` under the same id. The words are the ones the host's `perform` offered.
final class ChannelHostAgents: AgentHostAgents, @unchecked Sendable {
    let words: [String]
    private let channel: any AgentChannel
    private let lock = NSLock()
    private var next = 0
    private var waiting: [Int: CheckedContinuation<AgentWire.AgentCalled, Error>] = [:]
    private var abandoned: Set<Int> = []
    private var gone = false

    init(channel: any AgentChannel, words: [String]) {
        self.channel = channel
        self.words = words
    }

    func call(_ word: String, input: Data) async throws -> Data {
        guard let json = AgentJSON(data: input) else {
            throw AgentHostError.agent(word: word, refusal: nil, message: "the input is not JSON")
        }
        let called = try await send(word, json)
        if let output = called.output { return output.data() }
        throw AgentHostError.agent(word: word, refusal: called.refused, message: called.failed ?? "the host answered no output")
    }

    /// The host's answer to a call.
    func resolve(_ called: AgentWire.AgentCalled) {
        lock.withLock { waiting.removeValue(forKey: called.id) }?.resume(returning: called)
    }

    /// The host is gone: every call waiting, and every call after, ends without an answer.
    func leave() {
        let left = lock.withLock {
            gone = true
            defer { waiting = [:] }
            return Array(waiting.values)
        }
        for continuation in left { continuation.resume(throwing: AgentHostError.agent(word: "", refusal: nil, message: "the host is gone")) }
    }

    private func send(_ word: String, _ input: AgentJSON) async throws -> AgentWire.AgentCalled {
        let id = lock.withLock { next += 1; return next }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AgentWire.AgentCalled, Error>) in
                let refused: Error? = lock.withLock {
                    if abandoned.remove(id) != nil { return CancellationError() }
                    if gone { return AgentHostError.agent(word: word, refusal: nil, message: "the host is gone") }
                    waiting[id] = continuation
                    return nil
                }
                if let refused { return continuation.resume(throwing: refused) }
                do {
                    try channel.send(.agent(.init(id: id, word: word, input: input)))
                } catch {
                    lock.withLock { waiting.removeValue(forKey: id) }?
                        .resume(throwing: AgentHostError.agent(word: word, refusal: nil, message: "the call could not be sent: \(error)"))
                }
            }
        } onCancel: {
            let waiter: CheckedContinuation<AgentWire.AgentCalled, Error>? = lock.withLock {
                if let waiter = waiting.removeValue(forKey: id) { return waiter }
                abandoned.insert(id)
                return nil
            }
            waiter?.resume(throwing: CancellationError())
        }
    }
}
