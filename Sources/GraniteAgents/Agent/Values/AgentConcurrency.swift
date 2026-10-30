import Foundation

/// What a second send does while a run with the same key is live.
public enum AgentConcurrency: Sendable, Equatable {
    /// Cancel the live run and start this one (the default).
    case supersede
    /// Ignore this send.
    case drop
    /// Hand the input to the live run (`GraniteAgent.merge`): steering a run under way.
    case merge
    /// Run beside it, up to `max` at once; more wait their turn.
    case parallel(max: Int?)
}
