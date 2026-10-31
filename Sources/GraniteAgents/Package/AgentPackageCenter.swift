import Foundation
import Granite

/// The center a package agent runs on. Granite's, so a package declares no center, state or service of its
/// own; its state counts what the package's calls did.
public struct AgentPackageCenter<P: GraniteAgentPackage>: GraniteCenter {
    public struct State: TransientState {
        /// Calls that began.
        public var runs = 0
        public var finished = 0
        public var cancelled = 0
        public var failed = 0
        /// Events the runs streamed, folded or not.
        public var events = 0
        /// What the last failed call said.
        public var lastFailure: String?

        public init() {}
    }

    @Agent public var agent: AgentPackageRun<P>.Agent
    @Store public var state: State

    public init() {}
}
