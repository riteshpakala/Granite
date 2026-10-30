import Foundation

/// How an awaited run ended, when it finished. Cancellation throws `CancellationError`; a failure,
/// a supersession or a drop throws `AgentRunError`.
public struct AgentOutcome: Sendable, Equatable {
    public let run: AgentRunID
    /// The frames the run streamed, counted before they were folded into commits.
    public let frames: Int

    public init(run: AgentRunID, frames: Int) {
        self.run = run; self.frames = frames
    }
}
