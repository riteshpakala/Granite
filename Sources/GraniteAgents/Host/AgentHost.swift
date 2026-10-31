//  WHAT: What the app that runs a package offers the run beside its JSON: the folder it works in, what the
//        person asked, a line of progress the app shows, and the model it has loaded. A run reads it through
//        `context.host`.
//  PIN:  OFFERED, NEVER ASSUMED. `.none` offers nothing, so an app without a model still runs every package;
//        a package that cannot work without the model asks for it with `model(for:)`, which says whose run
//        went without.
//  PIN:  THE ASK IS NOT A PARAMETER. A model writes a call's input; it never writes what the person asked, so
//        the ask rides the host, not the schema, and never lands in the tool call a transcript keeps.

import Foundation

/// What a host offers a package run beside its input.
public struct AgentHost: Sendable {
    /// The folder the host works in; nil when it has none. An `Input` that declares `directory` is filled
    /// with the same folder.
    public let directory: String?
    /// What the person asked, in their words; nil when no person asked (a script, a test).
    public let ask: String?
    /// The model the host has loaded; nil when it has none.
    public let model: (any AgentHostModel)?
    /// A line of progress, shown as the host shows its agents' work (an agent map, a log).
    public let note: @Sendable (String) -> Void

    public init(directory: String? = nil, ask: String? = nil, model: (any AgentHostModel)? = nil,
                note: @escaping @Sendable (String) -> Void = { _ in }) {
        self.directory = directory; self.ask = ask; self.model = model; self.note = note
    }

    /// A host that offers nothing: a call made with JSON alone.
    public static let none = AgentHost()

    /// The host's model, or `AgentHostError.noModel` naming the package that asked for it.
    public func model(for word: String) throws -> any AgentHostModel {
        guard let model else { throw AgentHostError.noModel(word: word) }
        return model
    }
}
