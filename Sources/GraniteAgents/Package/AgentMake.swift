import Foundation

/// One kind of thing a package makes, as a fact a host acts on: what it is, where it lands, what it leaves to others.
///
/// ```swift
/// static let makes = [AgentMake(kind: "view", what: "the social screens as reusable SwiftUI views; pages show them",
///                               into: ["Shared/Views/Social/*"], never: "routes; never a page, a service or a model type")]
/// ```
///
/// PIN: `into` is relative to the host's folder, a `*` standing for one path component; a host reads a path under
/// it as this agent's to write.
public struct AgentMake: Codable, Sendable, Equatable, Hashable {
    /// The kind a call's `made` and `expected` items carry: one lowercase word.
    public var kind: String
    /// What it is, in the words a reading can match to a request.
    public var what: String
    /// Where it writes, relative to the host's folder.
    public var into: [String]
    /// What it never does, in a sentence.
    public var never: String?

    public init(kind: String, what: String, into: [String], never: String? = nil) {
        self.kind = kind; self.what = what; self.into = into; self.never = never
    }
}
