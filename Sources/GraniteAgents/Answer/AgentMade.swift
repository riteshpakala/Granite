import Foundation

/// One thing a call made: its kind (one its package declares), its name, the file it is in, and what happened to it.
public struct AgentMade: Codable, Sendable, Equatable, Hashable {
    public enum State: String, Codable, Sendable, CaseIterable {
        /// A file that was not there.
        case written
        /// A file that was there, written again with new text.
        case rewritten
        /// Written again to the same text: made, and nothing changed.
        case unchanged
        /// Taken away.
        case removed
    }

    public var kind: String
    public var name: String
    public var path: String?
    public var state: State

    public init(kind: String, name: String, path: String? = nil, state: State = .written) {
        self.kind = kind; self.name = name; self.path = path; self.state = state
    }
}
