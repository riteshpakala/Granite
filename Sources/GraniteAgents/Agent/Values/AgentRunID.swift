import Foundation

/// One run of an agent: unique in its executable, keyed by what the agent made of its input.
public struct AgentRunID: Hashable, Sendable, CustomStringConvertible {
    public static let defaultKey = "default"
    public let raw: String
    public let key: String
    /// The run that spawned this one, when one did.
    public let parent: String?

    public init(raw: String, key: String = AgentRunID.defaultKey, parent: String? = nil) {
        self.raw = raw; self.key = key; self.parent = parent
    }

    public var description: String { raw }
}
