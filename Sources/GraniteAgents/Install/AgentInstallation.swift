import Foundation

/// One installed runner, as `installation.json` keeps it beside the executable: where it came from, what it was
/// built with, the executable's digest, and what it carries. A host offers its agents from this alone; it never
/// runs the executable to find out.
public struct AgentInstallation: Codable, Sendable, Equatable {
    public static let format = "granite-agent-installation/1"
    public static let file = "installation.json"

    public var format: String
    /// The package's name, and the folder's.
    public var name: String
    public var source: AgentSource
    /// The source's commit, when it is a repository.
    public var revision: String?
    /// The Granite revision the runner was built against.
    public var granite: String?
    /// The executable, relative to the installation's folder.
    public var executable: String
    /// The executable's SHA-256, lowercase hex.
    public var sha256: String
    public var size: Int64
    /// The executable's modification time when installed, seconds since 1970: a launch skips the digest while
    /// the size and this still match.
    public var modified: Double?
    /// ISO 8601.
    public var builtAt: String
    public var entries: [AgentWire.Entry]

    public init(name: String, source: AgentSource, revision: String?, granite: String?, executable: String = "agent",
                sha256: String, size: Int64, modified: Double?, builtAt: String, entries: [AgentWire.Entry]) {
        format = Self.format
        self.name = name; self.source = source; self.revision = revision; self.granite = granite; self.executable = executable
        self.sha256 = sha256; self.size = size; self.modified = modified; self.builtAt = builtAt; self.entries = entries
    }

    /// The words of the agents it carries.
    public var words: [String] { entries.map(\.word) }
}
