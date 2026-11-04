import Foundation
import GraniteAgents

/// A package agent whose answer keeps `granite-answer/1`: it writes a card (a payload with a `schema` of its own)
/// into the host's folder, and answers well, or breaks the standard in the way its input names, or refuses.
struct MakerPackage: GraniteAgentPackage {
    struct Input: Codable, Sendable {
        var name: String
        /// `good`, `path`, `kind`, `payload`, `stamp`, `refuse`.
        var mode: String?
        var directory: String?
    }

    struct Answer: AgentAnswer, Equatable {
        var path: String?
        var paths: [String]
        var made: [AgentMade]
        var expected: [AgentExpected]
        var payloads: [AgentPayload]
        var notes: [String]
        var format: String?
        var card: String
    }

    typealias Event = Answer
    typealias Output = Answer
    typealias Compute = Void

    static let word = "maker"
    static let summary = "writes a card and says what it made."
    static let makes = [AgentMake(kind: "card", what: "a card of one name", into: ["cards/*"], never: "a page")]

    func run(_ input: Input, context: Context) -> AsyncThrowingStream<Answer, Error> {
        AsyncThrowingStream { continuation in
            do {
                let mode = input.mode ?? "good"
                if mode == "refuse" { throw AgentRefusal(.call, "`name` is empty: give the card a name") }
                let folder = URL(fileURLWithPath: input.directory ?? FileManager.default.currentDirectoryPath).appendingPathComponent("cards")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let file = folder.appendingPathComponent("\(input.name).card.json")
                let schema = mode == "payload" ? "other-card/1" : "test-card/1"
                try Data(#"{"schema": "\#(schema)", "name": "\#(input.name)"}"#.utf8).write(to: file)
                let relative = "cards/\(input.name).card.json"
                var answer = Answer(path: relative, paths: [relative],
                                    made: [AgentMade(kind: mode == "kind" ? "chart" : "card", name: input.name, path: file.path)],
                                    expected: [AgentExpected(kind: "card", name: input.name)],
                                    payloads: [AgentPayload(path: relative, schema: "test-card/1")], notes: ["one card"], card: input.name)
                if mode == "path" { answer.path = "cards/elsewhere.card.json" }
                if mode == "stamp" { answer.format = "made-up/9" }
                continuation.yield(answer)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
