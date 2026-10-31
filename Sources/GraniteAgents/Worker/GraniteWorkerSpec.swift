//  WHAT: A worker an app spawns beside its own agent, said without the app's types, so a package can ship
//        one: the word the app's model asks for it by, what it does, which of the app's tools it keeps, how
//        far it may go, and the words it is told. The app makes it one of its worker kinds; what a worker
//        is past these words is the app's.
//  PIN:  Found the way a package agent is: a record in `__DATA_CONST,__granite`
//        (`GraniteRoster.record(worker:)`), read by `GraniteRoster.discovered()`.

import Foundation

/// A worker kind that ships as a package.
///
/// ```swift
/// public enum Scout: GraniteWorkerSpec {
///     public static let word = "scout"
///     public static let summary = "maps a folder it is pointed at and says what each file is for."
/// }
///
/// @used @section("__DATA_CONST,__granite")
/// let scoutRecord: GraniteRoster.Record = { GraniteRoster.record(worker: Scout.self) }
/// ```
public protocol GraniteWorkerSpec: Sendable {
    /// The word an app's model asks for it by: lowercase, one word.
    static var word: String { get }
    /// What it does, said after its word, as a sentence.
    static var summary: String { get }
    /// The app's tools it keeps, by name. Default: none named, which keeps the app's reading set.
    static var toolNames: [String] { get }
    /// How far it may go. Default: `.reading`.
    static var budget: WorkerBudget { get }
    /// Whether it runs commands, and so is told what the app's shell is. Default: false.
    static var shell: Bool { get }
    /// Who it is, opening its prompt, given the word it was asked for by and the folder it works in.
    /// Default: nil, which keeps the app's own opening.
    static func opening(word: String, project: String) -> String?
    /// What its last message, the report, must say. Default: nil, the app's own rule.
    static var reportRule: String? { get }
}

extension GraniteWorkerSpec {
    public static var toolNames: [String] { [] }
    public static var budget: WorkerBudget { .reading }
    public static var shell: Bool { false }
    public static func opening(word: String, project: String) -> String? { nil }
    public static var reportRule: String? { nil }
}
