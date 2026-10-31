import Foundation

/// One call of a package agent: its own run, keyed by its id, so two calls never take each other's place.
public struct AgentPackageCall<Input: Sendable>: Sendable {
    public let id: String
    public let input: Input

    public init(id: String, input: Input) {
        self.id = id; self.input = input
    }
}
