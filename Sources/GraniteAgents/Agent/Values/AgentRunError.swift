import Foundation

public enum AgentRunError: Error, Equatable, CustomStringConvertible {
    /// `send` before `attach`: nothing to compute with.
    case noCompute(String)
    /// A send or a wait before the center compiled the agent.
    case notCompiled(String)
    /// `.drop`: a run with this key is live, so this one never began.
    case dropped(String)
    /// A later send with the same key took this run's place.
    case superseded(AgentRunID)
    /// The run's lifecycle was `.failed` with this message.
    case failed(AgentRunID, String)
    /// A wait on a run that is neither live nor waiting: it ended before anyone opened a wait.
    case unknownRun(AgentRunID)
    /// `perform` from inside the run it would wait on (`AgentRunScope`).
    case reentrant(AgentRunID)

    public var description: String {
        switch self {
        case .noCompute(let agent): return "\(agent) has no compute attached: call `$agent.attach { input in … }` from the composition root"
        case .notCompiled(let agent): return "\(agent) was used before its center compiled"
        case .dropped(let agent): return "\(agent) is already running for this key, and its policy drops a second send"
        case .superseded(let run): return "\(run) was replaced by a later send with the same key"
        case .failed(let run, let message): return "\(run) failed: \(message)"
        case .unknownRun(let run): return "\(run) is neither running nor waiting: open the wait in the turn that starts it"
        case .reentrant(let run): return "\(run) cannot wait on itself: reach a child through `context.spawn`"
        }
    }
}
