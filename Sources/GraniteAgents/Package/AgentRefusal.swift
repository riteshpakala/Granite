//  WHAT: Why a call was not answered, as a kind a host can count and reasons each saying its fix. One shape for
//        every agent: a call the agent cannot honour (`call`), an input it cannot read (`input`), a build or a
//        device that failed (`build`, `device`), a model that gave nothing usable (`model`), its own Swift that did
//        not parse (`parse`), a service it could not reach (`reach`), an answer that broke the standard (`answer`),
//        a host that could not serve it (`host`).
//  PIN:  A REFUSAL IS NOT A FAULT. An error that is neither an `AgentRefusal` nor `AgentRefusing` is the agent's
//        fault, said as it is; only a refusal is the call's to correct.

import Foundation

public struct AgentRefusal: Error, Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case input, call, build, device, model, parse, reach, answer, host
    }

    public var kind: Kind
    /// One sentence each, its fix in it.
    public var reasons: [String]

    public init(_ kind: Kind, _ reasons: [String]) { self.kind = kind; self.reasons = reasons }
    public init(_ kind: Kind, _ reason: String) { self.init(kind, [reason]) }

    /// One reason as it is; several as a count and a list.
    public var description: String {
        reasons.count == 1 ? reasons[0] : "\(reasons.count) problems, so nothing was done:\n" + reasons.map { "- " + $0 }.joined(separator: "\n")
    }

    private enum Keys: String, CodingKey { case kind, reasons }

    /// A kind a newer runner says and this reader does not know is read as `host`.
    public init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: Keys.self)
        kind = Kind(rawValue: try keyed.decode(String.self, forKey: .kind)) ?? .host
        reasons = try keyed.decode([String].self, forKey: .reasons)
    }

    public func encode(to encoder: Encoder) throws {
        var keyed = encoder.container(keyedBy: Keys.self)
        try keyed.encode(kind.rawValue, forKey: .kind)
        try keyed.encode(reasons, forKey: .reasons)
    }

    /// The refusal `error` is, when it is one: an `AgentRefusal`, an `AgentRefusing` error, Granite's own input and
    /// answer errors, a host model that could not answer. Nil: a fault.
    public static func of(_ error: any Error) -> AgentRefusal? {
        if let refusal = error as? AgentRefusal { return refusal }
        if let refusing = error as? any AgentRefusing { return refusing.refusal }
        if let package = error as? AgentPackageError {
            switch package {
            case .input(_, let reason): return AgentRefusal(.input, reason)
            case .noOutput(let word): return AgentRefusal(.answer, "\(word) finished without an answer")
            case .refused(_, let refusal, _): return refusal
            }
        }
        if let host = error as? AgentHostError { return AgentRefusal(.model, "\(host)") }
        return nil
    }
}

/// An agent's own error type that is a refusal, said as one: `extension LoomError: AgentRefusing { … }`.
public protocol AgentRefusing: Error {
    var refusal: AgentRefusal { get }
}
