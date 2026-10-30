import Foundation

/// The run the current task computes inside, when it is one: set by the container around `run`,
/// inherited by the tasks an agent's stream makes.
///
/// PIN: A RUN NEVER PERFORMS ITSELF. Under `.merge` it would steer the run that is waiting on it
/// (a deadlock); under any other policy it would supersede itself. `perform` reads this and throws
/// `AgentRunError.reentrant`; a run reaches its children through `context.spawn`.
public enum AgentRunScope {
    public struct Current: Sendable, Equatable {
        public let run: AgentRunID
        public let agent: ObjectIdentifier
        public init(run: AgentRunID, agent: ObjectIdentifier) { self.run = run; self.agent = agent }
    }

    @TaskLocal public static var current: Current?
}
