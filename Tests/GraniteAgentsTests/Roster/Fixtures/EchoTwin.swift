import Foundation
import GraniteAgents

/// A second package agent with the echo's word and no record: what a roster listed by hand must refuse.
struct EchoTwin: GraniteAgentPackage {
    struct Input: Codable, Sendable { var text: String }
    typealias Event = String
    typealias Output = String
    typealias Compute = Void

    static let word = "echo"
    static let summary = "the echo's twin."

    func run(_ input: Input, context: Context) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(input.text)
            continuation.finish()
        }
    }
}
