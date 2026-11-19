import Foundation
import GraniteAgents

/// A package agent that needs `echo`: it asks its host to call the agent it is told to, with the text it is given, and
/// says back what that agent answered. Told a word it does not need, it calls it anyway, which is its own fault.
struct NeedyPackage: GraniteAgentPackage {
    struct Input: Codable, Sendable {
        var word: String
        var text: String
    }

    struct Answer: Codable, Sendable, Equatable {
        var heard: String
        var words: [String]
    }

    typealias Event = Answer
    typealias Output = Answer
    typealias Compute = Void

    static let word = "needy"
    static let summary = "asks its host to call echo, and says back what echo said."
    static let needs = [AgentNeed(word: "echo", why: "says the text back twice", source: "https://example.com/EchoAgent")]

    func run(_ input: Input, context: Context) -> AsyncThrowingStream<Answer, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let agents = context.host.agents else { throw AgentHostError.noAgent(word: input.word, caller: Self.word) }
                    let said = try await agents.call(input.word, input: EchoCall(text: input.text, times: 2), as: String.self)
                    continuation.yield(Answer(heard: said, words: agents.words))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    struct EchoCall: Encodable { var text: String; var times: Int }
}

/// A host's agents that answer each word from a table, and keep what they were asked.
final class TableAgents: AgentHostAgents, @unchecked Sendable {
    private let table: [String: @Sendable (Data) throws -> Data]
    private let lock = NSLock()
    private var kept: [String] = []

    init(_ table: [String: @Sendable (Data) throws -> Data]) { self.table = table }

    var words: [String] { table.keys.sorted() }
    var called: [String] { lock.withLock { kept } }

    func call(_ word: String, input: Data) async throws -> Data {
        lock.withLock { kept.append(word) }
        guard let answer = table[word] else { throw AgentHostError.noAgent(word: word, caller: "?") }
        return try answer(input)
    }
}

@used @section("__DATA_CONST,__granite")
let needyRecord: GraniteRoster.Record = { GraniteRoster.record(NeedyPackage.self) }
