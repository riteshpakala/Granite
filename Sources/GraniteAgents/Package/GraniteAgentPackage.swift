//  WHAT: An agent that ships as a Swift package of its own: a word, what it does, a `Codable` input and
//        output, the compute it makes for itself, and a run that streams. The package declares no center,
//        state or service: Granite hosts the run on a center of its own (`AgentPackageCenter`), and an app
//        runs it by its word through its roster, JSON in and JSON out.
//  PIN:  A PACKAGE IS FOUND, NOT LISTED. Its record (`GraniteRoster.record`) is placed in the binary's
//        `__DATA_CONST,__granite` section; an app that links the package finds it with
//        `GraniteRoster.discovered()`, with nothing to edit when a package is added or removed.
//  PIN:  Compute is made on the first call, never when the app starts: a package that holds a GPU pipeline
//        or a model costs nothing until it is asked for.
//  PIN:  THE HOST PLACES IT, THE AGENT SAYS WHAT. A package says what it keeps between calls (`keeps`) and what
//        it reads of the person's files (`takes`); where the folder is, and which files arrive, are the host's
//        (`context.host.support`, `context.host.attachments`). A package never picks its own folder under `~`.

import Foundation

/// An agent that ships as a package: what it is called, what it takes and answers, and its run.
///
/// ```swift
/// public struct Marble: GraniteAgentPackage {
///     public struct Input: Codable, Sendable { public var path: String; public var filter: MarbleFilter? }
///     public typealias Event = MarbleFrame
///     public typealias Output = MarbleResult
///     public typealias Compute = MarbleCompute
///
///     public static let word = "marble"
///     public static let summary = "filters a photo on the GPU and writes the result beside it"
///     public static func compute() async throws -> MarbleCompute { try MarbleCompute() }
///     public static func output(from events: [MarbleFrame]) -> MarbleResult? { … }
///
///     public init() {}
///     public func run(_ input: Input, context: Context) -> AsyncThrowingStream<MarbleFrame, Error> { … }
/// }
///
/// @used @section("__DATA_CONST,__granite")
/// let marbleRecord: GraniteRoster.Record = { GraniteRoster.record(Marble.self) }
/// ```
///
/// PIN: an `Input` field named `directory` (a `String?`) is the host's: an app fills it with the folder it
/// works in and does not show it to a model. An `Output` that wrote files says where in `path` or `paths`; one
/// that conforms to `AgentAnswer` answers `granite-answer/1`, checked and stamped before it leaves the process.
/// PIN: what else the app offers — the person's ask, the files they attached (when `takes` covers them), a folder of
/// the agent's own (when it `keeps` something), a note it shows, the model it has loaded, the agents it `needs` —
/// a run reads through `context.host`, `.none` when the call came with JSON alone.
public protocol GraniteAgentPackage: Sendable {
    /// What a call carries, decoded from the caller's JSON. Its fields are the package's schema.
    associatedtype Input: Codable & Sendable
    /// What a run streams while it works.
    associatedtype Event: Sendable
    /// What a call answers, encoded as JSON.
    associatedtype Output: Codable & Sendable
    /// What every run computes with: made once, by `compute()`, on the first call.
    associatedtype Compute: Sendable

    typealias Context = AgentContext<Compute, Event>

    /// The word an app calls it by: lowercase, one word, unique among the agents an app links.
    static var word: String { get }
    /// What it does, in a sentence an app may show a person or a model.
    static var summary: String { get }
    /// A line per `Input` field, said beside the field in the schema. Default: none.
    static var fields: [String: String] { get }
    /// How to use it well, in its own words: what to ask it for, what to give it, what it answers best. A host
    /// puts it in its prompt when a person asks for the agent by name. Default: nothing.
    static var guide: String { get }
    /// How many calls run at once; more wait their turn. Nil: no bound. Default: 2.
    static var lanes: Int? { get }
    /// What it makes, each kind with where it lands: what a host routes to it, and the kinds its answer's `made` and
    /// `expected` may name. Default: nothing declared.
    static var makes: [AgentMake] { get }
    /// What it reads of the files the person attached, as UTType identifiers (`"public.image"`): a host hands a run
    /// only the files whose type conforms to one, in `context.host.attachments`. Default: nothing, so no file of the
    /// person's reaches it.
    static var takes: [String] { get }
    /// What it keeps between calls, in a sentence a host may show a person ("the signatures of the images you
    /// watermark"). Declaring one asks the host for a folder of the agent's own, `context.host.support`, which the
    /// host keeps across calls, installs and rebuilds. Default: nil, and no folder.
    static var keeps: String? { get }
    /// The agents it calls to do its work, each by its word (`AgentNeed`): a run calls them through
    /// `context.host.agents`, and may call no other. A host offers the ones it can serve. Default: none.
    static var needs: [AgentNeed] { get }

    /// Makes what every run computes with. Called once, on the first call.
    static func compute() async throws -> Compute
    /// What a call answers, read off the events its run streamed; nil when nothing it said answers.
    static func output(from events: [Event]) -> Output?

    init()
    /// The work, off main, in a task the host owns: `context.isCancelled` is the cooperative check.
    func run(_ input: Input, context: Context) -> AsyncThrowingStream<Event, Error>
}

extension GraniteAgentPackage {
    public static var fields: [String: String] { [:] }
    public static var guide: String { "" }
    public static var lanes: Int? { 2 }
    public static var makes: [AgentMake] { [] }
    public static var takes: [String] { [] }
    public static var keeps: String? { nil }
    public static var needs: [AgentNeed] { [] }
}

extension GraniteAgentPackage where Compute == Void {
    public static func compute() async throws {}
}

extension GraniteAgentPackage where Output == Event {
    /// The last event a run streamed.
    public static func output(from events: [Event]) -> Output? { events.last }
}
