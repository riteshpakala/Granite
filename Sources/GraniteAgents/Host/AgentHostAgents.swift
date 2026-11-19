//  WHAT: The agents a host calls for a package run: the ones the run's package needs (`GraniteAgentPackage.needs`), each
//        called by its word with JSON in and JSON out, as the host would call it for a person. Over the wire, each call is
//        an `agent` message under an id and its answer a `called` message under the same id.
//  PIN:  ITS OWN CALL. The host runs a needed agent as a call of its own (its own process, its own folder, its own lane);
//        nothing of the caller's reaches it but the folder they share and the JSON the caller wrote.
//  PIN:  A REFUSAL STAYS ONE. What the needed agent refuses or fails comes back as `AgentHostError.agent`, its kind kept, so
//        the caller can say whose refusal it was; the caller's own call is not what was wrong.

import Foundation

/// What a host offers a run that needs other agents.
public protocol AgentHostAgents: Sendable {
    /// The words this host can call for the run: the package's needs it found.
    var words: [String] { get }
    /// One call to the agent called `word`, with `input` as its JSON; its answer as JSON.
    func call(_ word: String, input: Data) async throws -> Data
}

extension AgentHostAgents {
    /// One call with typed input and output: the input encoded, the answer decoded.
    public func call<Input: Encodable, Output: Decodable>(_ word: String, input: Input, as output: Output.Type) async throws -> Output {
        let data = try await call(word, input: JSONEncoder().encode(input))
        do {
            return try JSONDecoder().decode(Output.self, from: data)
        } catch {
            throw AgentHostError.agent(word: word, refusal: nil, message: "its answer does not decode as \(Output.self): \(error)")
        }
    }
}

/// The host's agents narrowed to what a package declares: a call to a word it does not need is the package's own fault,
/// said before anything leaves the run.
struct DeclaredAgents: AgentHostAgents {
    let offered: any AgentHostAgents
    let caller: String
    let needs: [String]

    var words: [String] { offered.words.filter(needs.contains) }

    func call(_ word: String, input: Data) async throws -> Data {
        guard needs.contains(word) else { throw AgentHostError.undeclared(word: word, caller: caller) }
        guard offered.words.contains(word) else { throw AgentHostError.noAgent(word: word, caller: caller) }
        return try await offered.call(word, input: input)
    }
}
