import Foundation

/// What a call could only do in part, said so a host can count it: a kind (`fallback`, `model`, `skipped`, …) and a
/// sentence.
public struct AgentProblem: Codable, Sendable, Equatable, Hashable {
    public var kind: String
    public var text: String

    public init(kind: String, text: String) { self.kind = kind; self.text = text }
}
