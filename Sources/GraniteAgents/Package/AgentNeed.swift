//  WHAT: Another agent a package calls to do its work, by that agent's word: what it is needed for, and where it can
//        be had. A package that needs one asks its host to call it (`AgentHost.agents`); the host runs it as its own
//        call, in its own process, with its own folder, and hands the answer back.
//  PIN:  DECLARED, NEVER DISCOVERED. A run may call only the words its package declares in `needs`; a call to any other
//        is refused before it leaves the run. A host offers the needs it can serve and says which (`AgentHostAgents.words`).
//  PIN:  THE HOST FINDS IT. `source` is a hint for a host that installs from a repository; a host with a store finds the
//        agent there by its word first.

import Foundation

public struct AgentNeed: Codable, Sendable, Equatable, Hashable {
    /// The word the needed agent is called by: `veil`.
    public var word: String
    /// What it is needed for, in a sentence a host may show a person ("seals each rendered page").
    public var why: String
    /// Where it can be had when a host has no store to find it in: a git URL. Nil: the host finds it by its word.
    public var source: String?

    public init(word: String, why: String, source: String? = nil) {
        self.word = word; self.why = why; self.source = source
    }
}
