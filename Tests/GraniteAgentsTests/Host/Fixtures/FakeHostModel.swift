import Foundation
import GraniteAgents

/// A host model that answers the same JSON to every ask and keeps what it was asked.
final class FakeHostModel: AgentHostModel, @unchecked Sendable {
    struct Ask { let schema: Data; let system: String; let user: String }

    private let answer: String
    private let lock = NSLock()
    private var kept: [Ask] = []

    init(answer: String) { self.answer = answer }

    var asked: [Ask] { lock.withLock { kept } }

    func object(schema: Data, system: String, user: String, maxTokens: Int, seconds: Double) async throws -> Data {
        lock.withLock { kept.append(Ask(schema: schema, system: system, user: user)) }
        return Data(answer.utf8)
    }

    func text(system: String, user: String, maxTokens: Int, seconds: Double) async throws -> String {
        lock.withLock { kept.append(Ask(schema: Data(), system: system, user: user)) }
        return answer
    }
}
