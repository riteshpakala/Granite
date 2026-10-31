//  WHAT: An agent that ships as a Swift package of its own: a word, what it does, a `Codable` input and
//        output, the compute it makes for itself, and a run that streams. The package declares no center,
//        state or service: Granite hosts the run on a center of its own (`AgentPackageCenter`), and an app
//        runs it by its word through its roster, JSON in and JSON out.
//  PIN:  A PACKAGE IS FOUND, NOT LISTED. Its record (`GraniteRoster.record`) is placed in the binary's
//        `__DATA_CONST,__granite` section; an app that links the package finds it with
//        `GraniteRoster.discovered()`, with nothing to edit when a package is added or removed.
//  PIN:  Compute is made on the first call, never when the app starts: a package that holds a GPU pipeline
//        or a model costs nothing until it is asked for.

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
/// works in and does not show it to a model. An `Output` that wrote files says where in `path` or `paths`.
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
    /// How many calls run at once; more wait their turn. Nil: no bound. Default: 2.
    static var lanes: Int? { get }

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
    public static var lanes: Int? { 2 }
}

extension GraniteAgentPackage where Compute == Void {
    public static func compute() async throws {}
}

extension GraniteAgentPackage where Output == Event {
    /// The last event a run streamed.
    public static func output(from events: [Event]) -> Output? { events.last }
}
