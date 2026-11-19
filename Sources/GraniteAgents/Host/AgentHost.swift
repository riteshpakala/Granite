//  WHAT: What the app that runs a package offers the run beside its JSON: the folder it works in, what the
//        person asked, the files the person attached, a folder of the agent's own, a line of progress the app
//        shows, the model it has loaded, and the agents it calls for the package. A run reads it through `context.host`.
//  PIN:  OFFERED, NEVER ASSUMED. `.none` offers nothing, so an app without a model still runs every package;
//        a package that cannot work without the model asks for it with `model(for:)`, which says whose run
//        went without.
//  PIN:  THE ASK IS NOT A PARAMETER. A model writes a call's input; it never writes what the person asked, so
//        the ask rides the host, not the schema, and never lands in the tool call a transcript keeps. The files
//        the person attached and the agent's own folder ride it for the same reason.

import Foundation

/// What a host offers a package run beside its input.
public struct AgentHost: Sendable {
    /// The folder the host works in; nil when it has none. An `Input` that declares `directory` is filled
    /// with the same folder.
    public let directory: String?
    /// What the person asked, in their words; nil when no person asked (a script, a test).
    public let ask: String?
    /// The files the person attached that the host hands this run, absolute paths: only those whose type the
    /// package takes (`GraniteAgentPackage.takes`). Empty when there are none, or the package takes none.
    public let attachments: [String]
    /// A folder of the agent's own, which the host keeps across calls, installs and rebuilds: where it keeps what
    /// it must remember. Nil when the host offers none, or the package declares no `keeps`. Where it is, is the
    /// host's to say (`GraniteAgentPackage.keeps`).
    public let support: String?
    /// The model the host has loaded; nil when it has none.
    public let model: (any AgentHostModel)?
    /// The agents the host calls for the run: the package's `needs` it can serve. Nil when it serves none; a run sees
    /// only the words its package declares.
    public let agents: (any AgentHostAgents)?
    /// A line of progress, shown as the host shows its agents' work (an agent map, a log).
    public let note: @Sendable (String) -> Void

    public init(directory: String? = nil, ask: String? = nil, attachments: [String] = [], support: String? = nil,
                model: (any AgentHostModel)? = nil, agents: (any AgentHostAgents)? = nil,
                note: @escaping @Sendable (String) -> Void = { _ in }) {
        self.directory = directory; self.ask = ask; self.attachments = attachments; self.support = support
        self.model = model; self.agents = agents; self.note = note
    }

    /// A host that offers nothing: a call made with JSON alone.
    public static let none = AgentHost()

    /// The host's model, or `AgentHostError.noModel` naming the package that asked for it.
    public func model(for word: String) throws -> any AgentHostModel {
        guard let model else { throw AgentHostError.noModel(word: word) }
        return model
    }

    /// The host's agents, or `AgentHostError.noAgent` naming the package and the word it needs.
    public func agents(for word: String, needing need: String) throws -> any AgentHostAgents {
        guard let agents, agents.words.contains(need) else { throw AgentHostError.noAgent(word: need, caller: word) }
        return agents
    }

    /// The same host, offering `agents` instead.
    public func serving(_ agents: (any AgentHostAgents)?) -> AgentHost {
        AgentHost(directory: directory, ask: ask, attachments: attachments, support: support, model: model, agents: agents, note: note)
    }
}
