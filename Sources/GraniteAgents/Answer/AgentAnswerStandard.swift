import Foundation

/// The answer's standard: its id, stamped as `format`, and the keys it reserves.
public enum AgentAnswerStandard {
    public static let format = "granite-answer/1"
    /// The keys a host reads; every other key is the package's own.
    public static let reserved = ["format", "agent", "path", "paths", "notes", "made", "expected", "problems", "payloads"]
    /// The keys only the runner writes.
    public static let stamped = ["format", "agent"]
}
