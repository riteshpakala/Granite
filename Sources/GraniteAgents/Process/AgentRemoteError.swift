import Foundation

/// What a call to an agent in another process can say besides its output.
public enum AgentRemoteError: Error, Equatable, CustomStringConvertible {
    /// The agent ran and failed, and said why: from a runner that keeps no answer standard, where a refusal and a
    /// fault read the same.
    case failed(word: String, message: String)
    /// The agent refused the call, with its kind and reasons, in the sentence it said.
    case refused(word: String, refusal: AgentRefusal, message: String)
    /// The agent failed by its own fault, not the call's: what it threw was no refusal.
    case fault(word: String, message: String)
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
        case .refused(let word, let refusal, let message): return "\(word) refused (\(refusal.kind.rawValue)): \(message)"
        case .fault(let word, let message): return "\(word) failed by its own fault: \(message)"
        case .ended(let word, let status, let log):
            return "\(word)'s process ended (\(status)) without answering" + (log.isEmpty ? "" : ": \(log)")
        case .unreadable(let word, let reason): return "\(word)'s process broke the wire: \(reason)"
        case .changed(let word, let path):
            return "\(word)'s executable changed since it was installed (\(path)); install it again"
        case .spawn(let path, let reason): return "could not start \(path): \(reason)"
        }
    }
}
