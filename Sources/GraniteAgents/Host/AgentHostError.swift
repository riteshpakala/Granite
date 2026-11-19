import Foundation

/// What asking the host can say besides an answer.
public enum AgentHostError: Error, Equatable, CustomStringConvertible {
    /// The package asked for the host's model, and the host has none.
    case noModel(word: String)
    /// The model said nothing that parses, or its time was up.
    case noAnswer(String)
    /// The model's JSON did not decode as what was asked.
    case answer(String)
    /// The package needs `word`, and this host cannot call it: not installed, or a host that calls no agents.
    case noAgent(word: String, caller: String)
    /// The package called `word` without declaring it in `needs`: its own fault, never sent.
    case undeclared(word: String, caller: String)
    /// The agent the host called for the package refused or failed: its refusal when it was one, and what it said.
    case agent(word: String, refusal: AgentRefusal?, message: String)

    public var description: String {
        switch self {
        case .noModel(let word): return "\(word) asks the host's model, and this host has none loaded"
        case .noAnswer(let reason): return "the host's model gave no answer: \(reason)"
        case .answer(let reason): return "the host's model answered something that does not decode: \(reason)"
        case .noAgent(let word, let caller):
            return "\(caller) needs `\(word)`, and this host cannot call it: install `\(word)` beside `\(caller)`, then ask again"
        case .undeclared(let word, let caller):
            return "\(caller) called `\(word)`, which it does not declare in `needs`"
        case .agent(let word, let refusal, let message):
            return "`\(word)` " + (refusal.map { "refused (\($0.kind.rawValue))" } ?? "failed") + ": \(message)"
        }
    }

    /// Whether the package's own code is what went wrong, rather than what the host could serve.
    var isFault: Bool {
        if case .undeclared = self { return true }
        return false
    }
}
