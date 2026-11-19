import Foundation
import XCTest
@testable import GraniteAgents

/// The agent's side of the wire, without a process: one call answered, the host's model asked across the
/// channel, a call it cannot make refused, and a cancel ending the run.
@MainActor
final class AgentServerTests: XCTestCase {
    private let roster = GraniteRoster([.package(AnyAgentPackage(EchoPackage.self)), .package(AnyAgentPackage(HostedPackage.self)),
                                        .package(AnyAgentPackage(NeedyPackage.self))])

    private func call(_ perform: AgentWire.Perform, answering: (@Sendable (AgentWire.ModelAsk) -> AgentWire.ModelAnswer)? = nil,
                      calling: (@Sendable (AgentWire.AgentCall) -> AgentWire.AgentCalled)? = nil,
                      cancelAfter: Double? = nil) async -> (exit: AgentServer.Exit, heard: [AgentWire]) {
        let (host, agent) = MemoryChannel.pair()
        let roster = self.roster
        let served = Task { await AgentServer.serve(agent, roster: roster) }
        var heard: [AgentWire] = []
        for await message in host.messages {
            heard.append(message)
            switch message {
            case .hello:
                try? host.send(.perform(perform))
                if let cancelAfter {
                    Task { try? await Task.sleep(nanoseconds: UInt64(cancelAfter * 1e9)); try? host.send(.cancel) }
                }
            case .model(let ask): try? host.send(.answer(answering?(ask) ?? .init(id: ask.id, error: "no model")))
            case .agent(let call): try? host.send(.called(calling?(call) ?? .init(id: call.id, failed: "not called")))
            case .output, .failed: host.close()
            default: break
            }
            if case .output = message { break }
            if case .failed = message { break }
        }
        return (await served.value, heard)
    }

    func testOneCallIsAnsweredOnce() async {
        let (exit, heard) = await call(.init(word: "echo", input: .object(["text": .string("hi"), "times": .integer(3)])))
        XCTAssertEqual(exit, .answered)
        XCTAssertEqual(heard.first?.kind, "hello", "the agent speaks first")
        XCTAssertEqual(heard.last, .output(.string("hi hi hi")))
    }

    func testTheHostsModelIsAskedAcrossTheChannel() async {
        let (exit, heard) = await call(.init(word: "hosted", input: .object(["needsModel": .bool(true)]), directory: "/p", ask: "count",
                                             attachments: ["/c/beach.png"], support: "/s/Hosted", model: true),
                                       answering: { ask in .init(id: ask.id, object: .object(["n": .integer(7)])) })
        XCTAssertEqual(exit, .answered)
        XCTAssertTrue(heard.contains(.note("working")), "the run's note crossed")
        guard case .model(let ask)? = heard.first(where: { $0.kind == "model" }) else { return XCTFail("\(heard)") }
        XCTAssertEqual(ask.kind, .object)
        XCTAssertNotNil(ask.schema, "the schema of what it asked for came along")
        guard case .output(let output)? = heard.last, let answer = try? JSONDecoder().decode(HostedPackage.Answer.self, from: output.data()) else {
            return XCTFail("\(heard)")
        }
        XCTAssertEqual(answer.modelSaid, 7)
        XCTAssertEqual(answer.ask, "count")
        XCTAssertEqual(answer.hostDirectory, "/p")
        XCTAssertEqual(answer.attachments, ["/c/beach.png"], "the files crossed beside the input")
        XCTAssertEqual(answer.support, "/s/Hosted")
    }

    func testAHostWithoutAModelIsSaidSo() async {
        let (exit, heard) = await call(.init(word: "hosted", input: .object(["needsModel": .bool(true)]), model: false))
        XCTAssertEqual(exit, .refused, "a host with no model is a refusal of kind model, not a fault")
        guard case .failed(let failure)? = heard.last else { return XCTFail("\(heard)") }
        XCTAssertTrue(failure.message.contains("hosted asks the host's model"), failure.message)
        XCTAssertEqual(failure.refusal?.kind, .model)
    }

    func testACallItCannotMakeIsRefused() async {
        let (exit, heard) = await call(.init(word: "nobody", input: .object([:])))
        XCTAssertEqual(exit, .failed)
        XCTAssertEqual(heard.last, .failed("no agent is called `nobody` in this process; it carries `echo`, `hosted`, `needy`"))
    }

    /// An agent the package needs is called across the channel: an `agent` message under an id, the host's `called`
    /// under the same id, the words the run sees being the ones the host offered that the package needs.
    func testANeededAgentIsCalledAcrossTheChannel() async {
        let (exit, heard) = await call(.init(word: "needy", input: .object(["word": .string("echo"), "text": .string("hi")]),
                                             agents: ["echo", "hosted"]),
                                       calling: { call in .init(id: call.id, output: .string("hi hi")) })
        XCTAssertEqual(exit, .answered)
        guard case .agent(let asked)? = heard.first(where: { $0.kind == "agent" }) else { return XCTFail("\(heard)") }
        XCTAssertEqual(asked.word, "echo")
        XCTAssertEqual(asked.input, .object(["text": .string("hi"), "times": .integer(2)]))
        guard case .output(let output)? = heard.last, let answer = try? JSONDecoder().decode(NeedyPackage.Answer.self, from: output.data()) else {
            return XCTFail("\(heard)")
        }
        XCTAssertEqual(answer, NeedyPackage.Answer(heard: "hi hi", words: ["echo"]))
    }

    /// A word the package never declared is never sent, even when the host would call it: the run fails by its own fault.
    func testAWordItDoesNotNeedIsNeverSent() async {
        let (exit, heard) = await call(.init(word: "needy", input: .object(["word": .string("hosted"), "text": .string("hi")]),
                                             agents: ["echo", "hosted"]))
        XCTAssertEqual(exit, .failed, "its own fault, not a refusal")
        XCTAssertFalse(heard.contains { $0.kind == "agent" }, "\(heard)")
    }

    /// A host that offers no agents, and an agent the host called that refused, are both the host's refusal.
    func testWithoutTheAgentItNeedsTheCallIsTheHostsRefusal() async {
        let (exit, heard) = await call(.init(word: "needy", input: .object(["word": .string("echo"), "text": .string("hi")])))
        XCTAssertEqual(exit, .refused)
        guard case .failed(let failure)? = heard.last else { return XCTFail("\(heard)") }
        XCTAssertEqual(failure.refusal?.kind, .host)

        let (refusedExit, refusedHeard) = await call(.init(word: "needy", input: .object(["word": .string("echo"), "text": .string("hi")]),
                                                           agents: ["echo"]),
                                                     calling: { call in .init(id: call.id, failed: "no text", refused: AgentRefusal(.input, "no text")) })
        XCTAssertEqual(refusedExit, .refused)
        guard case .failed(let refused)? = refusedHeard.last else { return XCTFail("\(refusedHeard)") }
        XCTAssertEqual(refused.refusal?.kind, .host)
        XCTAssertTrue(refused.message.contains("`echo` refused (input): no text"), refused.message)
    }

    func testACancelEndsTheRun() async {
        let (exit, heard) = await call(.init(word: "echo", input: .object(["text": .string("late"), "delay": .number(5)])), cancelAfter: 0.2)
        XCTAssertEqual(exit, .cancelled)
        XCTAssertEqual(heard.last, .failed("cancelled"))
    }
}
