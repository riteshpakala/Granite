import Foundation

/// How a run begins and ends, as the writer reduces it.
public enum AgentLifecycle: Sendable, Equatable {
    case started
    case finished
    case cancelled
    case failed(String)
}
