import Foundation

/// What a spawned child's run says to its parent: announced, each event, and how it ended.
/// The parent maps these into its own events (`AgentContext.spawn`), so whatever draws the
/// parent's events draws its children by construction.
public enum ChildFrame<Event: Sendable>: Sendable {
    case started(AgentRunID, kind: String, prompt: String)
    case event(AgentRunID, Event)
    case finished(AgentRunID, AgentLifecycle)
}
