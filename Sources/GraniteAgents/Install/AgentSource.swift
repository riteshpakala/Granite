import Foundation

/// Where an agent package's code is: a git repository, at a revision or its default branch's head, a folder on this
/// machine, or a store's listing, whose code the store hands over when asked (``AgentDeliverer``).
public enum AgentSource: Codable, Sendable, Equatable, CustomStringConvertible {
    case git(url: String, revision: String?)
    case path(String)
    /// A listing a store delivers: its code is fetched fresh from the store on every install and update, at
    /// whatever the listing pins then, so nothing kept on disk names an address that expires.
    case delivered(id: String)

    /// `https://github.com/rao/PlateAgent.git`, `…/PlateAgent.git@f9bdda7`, `git@github.com:rao/PlateAgent.git`, or a
    /// folder: `/abs/path`, `~/path`, `./path`, `../path`. A folder is resolved against `base`.
    public init(_ said: String, base: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
        let said = said.trimmingCharacters(in: .whitespaces)
        if said.hasPrefix("/") || said.hasPrefix("~") || said.hasPrefix(".") {
            let expanded = (said as NSString).expandingTildeInPath
            let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : base.appendingPathComponent(expanded)
            self = .path(url.standardizedFileURL.path)
            return
        }
        // A revision follows the last `@` after the last `/`: `git@host:x/y.git` has none.
        if let at = said.lastIndex(of: "@"), let slash = said.lastIndex(of: "/"), at > slash {
            self = .git(url: String(said[..<at]), revision: String(said[said.index(after: at)...]))
        } else {
            self = .git(url: said, revision: nil)
        }
    }

    public var description: String {
        switch self {
        case .git(let url, let revision): return url + (revision.map { "@" + $0 } ?? "")
        case .path(let path): return path
        case .delivered(let id): return "delivered:" + id
        }
    }

    private enum Key: String, CodingKey { case url, revision, path, delivered }

    /// `{"url": "…", "revision": "…"}`, `{"path": "…"}` or `{"delivered": "…"}`.
    public init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: Key.self)
        if let id = try keyed.decodeIfPresent(String.self, forKey: .delivered) {
            self = .delivered(id: id)
        } else if let path = try keyed.decodeIfPresent(String.self, forKey: .path) {
            self = .path(path)
        } else {
            self = .git(url: try keyed.decode(String.self, forKey: .url), revision: try keyed.decodeIfPresent(String.self, forKey: .revision))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var keyed = encoder.container(keyedBy: Key.self)
        switch self {
        case .git(let url, let revision):
            try keyed.encode(url, forKey: .url)
            try keyed.encodeIfPresent(revision, forKey: .revision)
        case .path(let path):
            try keyed.encode(path, forKey: .path)
        case .delivered(let id):
            try keyed.encode(id, forKey: .delivered)
        }
    }

    /// The same source at its newest: a repository's head, a folder as it is, a listing at what its store pins now.
    public var newest: AgentSource {
        if case .git(let url, _) = self { return .git(url: url, revision: nil) }
        return self
    }
}
