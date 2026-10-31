import Foundation
import GraniteAgents

/// A package agent the runner fixture carries, to exercise every message of the wire: it says its text back,
/// notes as it goes, asks the host's model when told, waits when told, and crashes when told.
struct ParrotPackage: GraniteAgentPackage {
    struct Input: Codable, Sendable {
        var text: String
        var notes: Int?
        var askModel: Bool?
        var delay: Double?
        var crash: Bool?
        var fail: Bool?
        var directory: String?
    }

    struct Said: Codable, Sendable, Equatable {
        var said: String
        var modelSaid: Int?
        var directory: String?
        var hostDirectory: String?
        var ask: String?
        var pid: Int32
    }

    struct Count: Decodable { let n: Int }
    struct Failure: Error, CustomStringConvertible { var description: String { "told to fail" } }

    typealias Event = Said
    typealias Output = Said
    typealias Compute = Void

    static let word = "parrot"
    static let summary = "says its text back, in a process of its own."
    static let fields = ["text": "what to say"]
    static let guide = "Give it text; it says it back."

    func run(_ input: Input, context: Context) -> AsyncThrowingStream<Said, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    print("this line must not reach the wire")
                    for index in 0..<(input.notes ?? 0) { context.host.note("note \(index + 1)") }
                    if input.crash == true { abort() }
                    if input.fail == true { throw Failure() }
                    if let delay = input.delay { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                    var said = Said(said: input.text, directory: input.directory, hostDirectory: context.host.directory,
                                    ask: context.host.ask, pid: getpid())
                    if input.askModel == true {
                        said.modelSaid = try await context.host.model(for: Self.word).object(Count.self, system: "Count.", user: "How many?",
                                                                                              maxTokens: 16, seconds: 5).n
                    }
                    continuation.yield(said)
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
let parrotRecord: GraniteRoster.Record = { GraniteRoster.record(ParrotPackage.self) }
