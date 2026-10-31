import Foundation
import GraniteAgents

/// A child agent that says the ask its host offered: how a test sees that a child inherits its parent's host.
struct AskChild: GraniteAgent {
    typealias Center = CounterCenter
    typealias Input = Int
    typealias Event = String
    typealias Compute = Int

    func run(_ input: Int, context: Context) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(context.host.ask ?? "no ask")
            continuation.finish()
        }
    }

    func reduce(state: inout CounterCenter.State, event: String, run: AgentRunID) {}
}
