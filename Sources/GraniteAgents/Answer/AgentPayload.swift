import Foundation

/// A file among a call's `paths` that follows a standard of its own: its path and the id its own `schema` key says
/// (`craft-timeseries/1`). The answer names it; the file carries it.
public struct AgentPayload: Codable, Sendable, Equatable, Hashable {
    public var path: String
    public var schema: String

    public init(path: String, schema: String) { self.path = path; self.schema = schema }
}
