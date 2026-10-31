import Foundation
import GraniteAgents

/// A package agent with a record in this test binary: says its text back, as many times as asked, after a
/// delay when given one.
struct EchoPackage: GraniteAgentPackage {
    struct Input: Codable, Sendable {
        var text: String
        var times: Int?
        var delay: Double?
        var directory: String?
    }
    typealias Event = String
    typealias Output = String
    typealias Compute = Void

    static let word = "echo"
    static let summary = "says its text back, as many times as it is asked."
    static let fields = ["text": "what to say", "times": "how many times; once when left out"]

    func run(_ input: Input, context: Context) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                if let delay = input.delay { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                if !Task.isCancelled, !context.isCancelled() {
                    continuation.yield(Array(repeating: input.text, count: max(1, input.times ?? 1)).joined(separator: " "))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@used @section("__DATA_CONST,__granite")
let echoRecord: GraniteRoster.Record = { GraniteRoster.record(EchoPackage.self) }
