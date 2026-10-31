import Foundation
import GraniteAgents

/// A package agent with a record in this test binary that says back what its host offered: the ask, the
/// folder, what the host's model answered when asked, and what a child it spawned heard.
struct HostedPackage: GraniteAgentPackage {
    struct Input: Codable, Sendable {
        var needsModel: Bool?
        var spawn: Bool?
        var directory: String?
    }

    struct Answer: Codable, Sendable, Equatable {
        var ask: String?
        var directory: String?
        var hostDirectory: String?
        var modelSaid: Int?
        var childAsk: String?
    }

    /// What the host's model is asked for.
    struct Count: Decodable { let n: Int }

    typealias Event = Answer
    typealias Output = Answer
    typealias Compute = Void

    static let word = "hosted"
    static let summary = "says back what its host offered it."
    static let guide = "Ask it what the host offered; it says it back, and asks the model when told to."

    func run(_ input: Input, context: Context) -> AsyncThrowingStream<Answer, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    context.host.note("working")
                    var answer = Answer(ask: context.host.ask, directory: input.directory, hostDirectory: context.host.directory)
                    if input.needsModel == true {
                        let model = try context.host.model(for: Self.word)
                        answer.modelSaid = try await model.object(Count.self, system: "Count.", user: "How many?", maxTokens: 16, seconds: 5).n
                    }
                    if input.spawn == true {
                        let child = context.spawn(AskChild(), input: 0, compute: 0, id: "child-1", kind: "child", prompt: "say the ask") { frame -> Answer? in
                            if case .event(_, let said) = frame { return Answer(childAsk: said) }
                            return nil
                        }
                        for await heard in child { answer.childAsk = heard.childAsk }
                    }
                    continuation.yield(answer)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@used @section("__DATA_CONST,__granite")
let hostedRecord: GraniteRoster.Record = { GraniteRoster.record(HostedPackage.self) }
