//  WHAT: What a package call answers, as every host reads it: `granite-answer/1`. The files it wrote, what it made
//        of what its call asked for, what it could only do in part, and the files whose own standard a host reads
//        (a `craft-timeseries/1` series): reserved keys at the top of the one JSON object a call answers, beside the
//        package's own, which a host passes on without reading.
//  PIN:  OPT-IN, THEN THE RULE. An `Output` that conforms is checked and stamped by the runner (`AnyAgentPackage`);
//        one that does not answers as it always did. Once every agent conforms, `Output: AgentAnswer` is the
//        requirement, so an install from an older agent never stops building in between.
//  PIN:  THE RUNNER STAMPS, THE AGENT NEVER DOES: `format` and `agent` are written after the output is encoded,
//        and an output that encodes either is refused as a bad answer.

import Foundation

/// The answer a package call gives: `paths` always, and what it made, expected, could not do and wrote in another
/// standard when it has them to say. Each defaults to nothing, so an answer that wrote files and said notes conforms
/// by naming `paths`.
public protocol AgentAnswer: Codable, Sendable {
    /// Every file the call wrote or removed, absolute or relative to the host's `directory`. `[]` when none.
    var paths: [String] { get }
    /// What the model should know: one sentence each.
    var notes: [String] { get }
    /// What the call made, one item each, by a kind its package declares (`GraniteAgentPackage.makes`).
    var made: [AgentMade] { get }
    /// What the call asked for, as the package read it: the measure `made` is held to.
    var expected: [AgentExpected] { get }
    /// What the call could only do in part: a fallback taken, a model that said nothing. Not a refusal.
    var problems: [AgentProblem] { get }
    /// Files among `paths` that follow a standard of their own, named by the `schema` key inside each.
    var payloads: [AgentPayload] { get }
}

extension AgentAnswer {
    public var notes: [String] { [] }
    public var made: [AgentMade] { [] }
    public var expected: [AgentExpected] { [] }
    public var problems: [AgentProblem] { [] }
    public var payloads: [AgentPayload] { [] }
}
