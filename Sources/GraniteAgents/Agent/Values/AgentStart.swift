import Foundation

/// What a send did, as `AgentExecutable.start` reports it on main.
public enum AgentStart: Sendable, Equatable {
    /// A run began.
    case started(AgentRunID)
    /// `.parallel` at its max: the run has its id now and begins when a lane frees.
    case queued(AgentRunID)
    /// `.merge`: the input went to the live run.
    case merged(into: AgentRunID)
    /// `.drop`: a run with this key is live; nothing happened.
    case dropped

    /// The run this send is part of, when it is part of one.
    public var run: AgentRunID? {
        switch self {
        case .started(let run), .queued(let run), .merged(let run): return run
        case .dropped: return nil
        }
    }
}
