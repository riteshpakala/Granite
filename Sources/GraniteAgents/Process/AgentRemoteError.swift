import Foundation

/// What a call to an agent in another process can say besides its output.
public enum AgentRemoteError: Error, Equatable, CustomStringConvertible {
    /// The agent ran and failed, and said why.
    case failed(word: String, message: String)
    /// The process ended without answering: crashed, killed, or never spoke the wire. `log` is the end of what
    /// it wrote to stderr.
    case ended(word: String, status: String, log: String)
    /// The process said something the wire does not allow where it said it.
    case unreadable(word: String, reason: String)
    /// The executable is not the one that was installed.
    case changed(word: String, path: String)
    /// The executable could not be started.
    case spawn(path: String, reason: String)

    public var description: String {
        switch self {
        case .failed(let word, let message): return "\(word) failed: \(message)"
        case .ended(let word, let status, let log):
            return "\(word)'s process ended (\(status)) without answering" + (log.isEmpty ? "" : ": \(log)")
        case .unreadable(let word, let reason): return "\(word)'s process broke the wire: \(reason)"
        case .changed(let word, let path):
            return "\(word)'s executable changed since it was installed (\(path)); install it again"
        case .spawn(let path, let reason): return "could not start \(path): \(reason)"
        }
    }
}
