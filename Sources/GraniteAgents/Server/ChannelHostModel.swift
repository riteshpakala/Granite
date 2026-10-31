import Foundation

/// The host's model, as an agent in another process asks it: each ask a `model` message under an id, each
/// answer the host's `answer` under the same id.
final class ChannelHostModel: AgentHostModel, @unchecked Sendable {
    private let channel: any AgentChannel
    private let lock = NSLock()
    private var next = 0
    private var waiting: [Int: CheckedContinuation<AgentWire.ModelAnswer, Error>] = [:]
    private var abandoned: Set<Int> = []
    private var gone = false

    init(channel: any AgentChannel) { self.channel = channel }

    func object(schema: Data, system: String, user: String, maxTokens: Int, seconds: Double) async throws -> Data {
        let answer = try await ask(.object, schema: AgentJSON(data: schema), system: system, user: user, maxTokens: maxTokens, seconds: seconds)
        if let error = answer.error { throw AgentHostError.noAnswer(error) }
        guard let object = answer.object else { throw AgentHostError.noAnswer("the host answered no object") }
        return object.data()
    }

    func text(system: String, user: String, maxTokens: Int, seconds: Double) async throws -> String {
        let answer = try await ask(.text, schema: nil, system: system, user: user, maxTokens: maxTokens, seconds: seconds)
        if let error = answer.error { throw AgentHostError.noAnswer(error) }
        return answer.text ?? ""
    }

    /// The host's answer to an ask.
    func resolve(_ answer: AgentWire.ModelAnswer) {
        lock.withLock { waiting.removeValue(forKey: answer.id) }?.resume(returning: answer)
    }

    /// The host is gone: every ask waiting, and every ask after, ends without an answer.
    func leave() {
        let left = lock.withLock {
            gone = true
            defer { waiting = [:] }
            return Array(waiting.values)
        }
        for continuation in left { continuation.resume(throwing: AgentHostError.noAnswer("the host is gone")) }
    }

    private func ask(_ kind: AgentWire.ModelAsk.Kind, schema: AgentJSON?, system: String, user: String, maxTokens: Int,
                     seconds: Double) async throws -> AgentWire.ModelAnswer {
        let id = lock.withLock { next += 1; return next }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AgentWire.ModelAnswer, Error>) in
                let refused: Error? = lock.withLock {
                    if abandoned.remove(id) != nil { return CancellationError() }
                    if gone { return AgentHostError.noAnswer("the host is gone") }
                    waiting[id] = continuation
                    return nil
                }
                if let refused { return continuation.resume(throwing: refused) }
                do {
                    try channel.send(.model(.init(id: id, kind: kind, schema: schema, system: system, user: user, maxTokens: maxTokens, seconds: seconds)))
                } catch {
                    lock.withLock { waiting.removeValue(forKey: id) }?.resume(throwing: AgentHostError.noAnswer("the ask could not be sent: \(error)"))
                }
            }
        } onCancel: {
            let waiter: CheckedContinuation<AgentWire.ModelAnswer, Error>? = lock.withLock {
                if let waiter = waiting.removeValue(forKey: id) { return waiter }
                abandoned.insert(id)
                return nil
            }
            waiter?.resume(throwing: CancellationError())
        }
    }
}
