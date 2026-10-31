import Foundation

/// One call of a package agent: its own run, keyed by its id, so two calls never take each other's place, and
/// what the app that made it offers the run.
public struct AgentPackageCall<Input: Sendable>: Sendable {
    public let id: String
    public let input: Input
    public let host: AgentHost

    public init(id: String, input: Input, host: AgentHost = .none) {
        self.id = id; self.input = input; self.host = host
    }
}
