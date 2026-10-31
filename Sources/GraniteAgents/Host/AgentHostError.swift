import Foundation

/// What asking the host can say besides an answer.
public enum AgentHostError: Error, Equatable, CustomStringConvertible {
    /// The package asked for the host's model, and the host has none.
    case noModel(word: String)
    /// The model said nothing that parses, or its time was up.
    case noAnswer(String)
    /// The model's JSON did not decode as what was asked.
    case answer(String)

    public var description: String {
        switch self {
        case .noModel(let word): return "\(word) asks the host's model, and this host has none loaded"
        case .noAnswer(let reason): return "the host's model gave no answer: \(reason)"
        case .answer(let reason): return "the host's model answered something that does not decode: \(reason)"
        }
    }
}
