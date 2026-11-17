//  WHAT: What an answer asks a client to do with the files it made, in words any client reads: a `kind` (`preview`:
//        show these to the person, the first in front), the files it is about, lead first, and a caption. Part of
//        `granite-answer/1` (`AgentAnswer.interactions`).
//  PIN:  THE AGENT ASKS, THE CLIENT DECIDES. An answer never names a client's UI: a client performs each interaction
//        it has a compatible way to, and ignores the rest. The files are in `paths` either way, so a client that
//        has none loses nothing, and a kind it does not know is never a failure.

import Foundation

/// One thing an answer asks a client to do with what the call made.
///
/// ```swift
/// var interactions: [AgentInteraction] { [.preview(["veil/beach.marked.png", "veil/beach.digest.png"], title: "Watermarked")] }
/// ```
public struct AgentInteraction: Codable, Sendable, Equatable, Hashable {
    /// Show these files to the person, the first in front.
    public static let previewKind = "preview"

    /// What is asked, as one lowercase word: an open vocabulary, of which the standard names `preview` first.
    public var kind: String
    /// The files it is about, lead first: each one of the answer's `paths`, on disk.
    public var paths: [String]
    /// A caption a client may show beside them.
    public var title: String?

    public init(kind: String, paths: [String], title: String? = nil) {
        self.kind = kind; self.paths = paths; self.title = title
    }

    /// Asks a client to show `paths` to the person, the first in front.
    public static func preview(_ paths: [String], title: String? = nil) -> AgentInteraction {
        AgentInteraction(kind: previewKind, paths: paths, title: title)
    }
}
