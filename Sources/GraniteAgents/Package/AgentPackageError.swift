import Foundation

/// What a package call can say besides its output.
public enum AgentPackageError: Error, Equatable, CustomStringConvertible {
    /// The call's JSON did not decode as the package's `Input`.
    case input(word: String, reason: String)
    /// The run ended without an event that answers (`output(from:)` said nil).
    case noOutput(word: String)

    public var description: String {
        switch self {
        case .input(let word, let reason): return "\(word) could not read its input: \(reason)"
        case .noOutput(let word): return "\(word) finished without an answer"
        }
    }
}
