import Foundation
import Granite

/// An agent, declared in a center the way an event is:
///
///     @Agent(.merge) var chat: Chat.Agent
///     @Agent(.parallel(max: 4)) var filter: Filter.Agent
///     @Agent(.onTask) var watcher: Watcher.Agent
///
/// Compiled by the center's own pass through `GraniteCustomEvent` (Granite's public hook for a
/// wrapper declared outside its core), so a send reaches a run the same way a send reaches a reducer. The wrapped and the
/// projected value are the same handle: `chat.send(…)`, `$chat.perform(…)`, `$chat.cancel()`,
/// `$chat.events()`, `$chat.attach { … }`.
///
/// PIN: THE DECLARATION'S CONCURRENCY WINS. The agent's static `concurrency` is its default, used
/// when the declaration names none.
@propertyWrapper
public struct Agent<A: GraniteAgent>: GraniteCustomEvent {
    public let forwarding: Forwarding = .none
    public let lifecycle: Lifecycle
    public let intermediateSignal = GraniteSignal.Payload<GranitePayload?>()
    public let executable: AgentExecutable<A>

    public var signal: GraniteSignal.Payload<GranitePayload?> { executable.signal }
    public var wrappedValue: AgentExecutable<A> { executable }
    public var projectedValue: AgentExecutable<A> { executable }

    public init(_ lifecycle: Lifecycle = .none) {
        self.lifecycle = lifecycle
        self.executable = AgentExecutable<A>()
    }

    public init(_ concurrency: AgentConcurrency, _ lifecycle: Lifecycle = .none) {
        self.lifecycle = lifecycle
        self.executable = AgentExecutable<A>(concurrency: concurrency)
    }

    public func compile(with host: GraniteEventHost) -> [any GraniteEventContainer] {
        [executable.compile(with: host)]
    }
}
