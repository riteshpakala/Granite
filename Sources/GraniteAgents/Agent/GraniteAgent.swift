import Foundation
import Granite

/// WHAT: An agent as a Granite center declares one — `@Agent var chat: Chat.Agent`. A send
///       starts a run; the run computes in its own task and streams events; each event is
///       reduced into the center's state by one writer, on main, keyed by run so a late frame
///       of a superseded run is dropped. Children a run spawns are announced the same way.
/// PIN:  Granite owns durable state; the run owns compute. `run` never touches state and
///       `reduce` never computes. What a run computes with is handed to it (`Compute`), attached by
///       the composition root: a model session, a Metal pipeline, a speech recognizer — nothing
///       in the wrapper names a kind of machine learning.
/// PIN:  Two ways to start a run, the two a reducer has: `send` (its effect ends; the run's frames
///       land on later turns) and `perform` (its effect awaits the run, then writes through its service's writer).
/// PIN:  `send` is main-only, as every Granite send is (an off-main send hops). Frames are
///       committed on main, one commit per drain, fresh state each time: a `.task` reducer's
///       entry snapshot would overwrite whatever else wrote meanwhile; this never does.
public protocol GraniteAgent: Sendable {
    associatedtype Center: GraniteCenter
    /// What a send carries: the ask, and which session or key it is for.
    associatedtype Input: Sendable
    /// What a run streams.
    associatedtype Event: Sendable
    /// What a run computes with: resolved by the composition root (`AgentExecutable.attach`).
    associatedtype Compute: Sendable

    typealias Agent = AgentExecutable<Self>
    typealias Context = AgentContext<Compute, Event>

    /// What a second send does while a run with the same key is live. Default `.supersede`.
    static var concurrency: AgentConcurrency { get }
    /// Which runs are "the same": one key per agent by default; per session for a session agent.
    static func key(_ input: Input) -> String
    /// The input a run begun by the host's lifecycle (`@Agent(.onTask)`) starts with; nil, the
    /// default, means such a wrapper starts nothing on its own.
    static var lifecycleInput: Input? { get }

    /// Compute. Runs off main in its own task; never touches state. Children go through
    /// `context.spawn`, and `context.isCancelled` is the cooperative check.
    func run(_ input: Input, context: Context) -> AsyncThrowingStream<Event, Error>
    /// The single writer: fresh state every drain, on main, keyed by run.
    func reduce(state: inout Center.GenericGraniteState, event: Event, run: AgentRunID)
    /// The run began, ended, was cancelled or failed.
    func reduce(state: inout Center.GenericGraniteState, lifecycle: AgentLifecycle, run: AgentRunID)
    /// A re-send while live, under `.merge`.
    func merge(_ input: Input, into run: AgentRunID, context: Context) async
    /// Two queued frames folded into one (text deltas), so main commits once per drain.
    static func coalesce(_ a: Event, _ b: Event) -> Event?

    init()
}

extension GraniteAgent {
    public static var concurrency: AgentConcurrency { .supersede }
    public static func key(_ input: Input) -> String { AgentRunID.defaultKey }
    public static var lifecycleInput: Input? { nil }
    public func reduce(state: inout Center.GenericGraniteState, lifecycle: AgentLifecycle, run: AgentRunID) {}
    public func merge(_ input: Input, into run: AgentRunID, context: Context) async {}
    public static func coalesce(_ a: Event, _ b: Event) -> Event? { nil }
}
