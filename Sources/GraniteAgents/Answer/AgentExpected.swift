import Foundation

/// One thing a call asked for, as its package read the call: by the kind and name a `made` item would carry.
public struct AgentExpected: Codable, Sendable, Equatable, Hashable {
    public var kind: String
    public var name: String

    public init(kind: String, name: String) { self.kind = kind; self.name = name }
}
