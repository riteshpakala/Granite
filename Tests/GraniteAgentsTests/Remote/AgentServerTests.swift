import Foundation
import XCTest
@testable import GraniteAgents

/// The agent's side of the wire, without a process: one call answered, the host's model asked across the
/// channel, a call it cannot make refused, and a cancel ending the run.
@MainActor
final class AgentServerTests: XCTestCase {
    private let roster = GraniteRoster([.package(AnyAgentPackage(EchoPackage.self)), .package(AnyAgentPackage(HostedPackage.self))])

    private func call(_ perform: AgentWire.Perform, answering: (@Sendable (AgentWire.ModelAsk) -> AgentWire.ModelAnswer)? = nil,
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
        let (exit, heard) = await call(.init(word: "hosted", input: .object(["needsModel": .bool(true)]), directory: "/p", ask: "count", model: true),
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
        XCTAssertEqual(heard.last, .failed("no agent is called `nobody` in this process; it carries `echo`, `hosted`"))
    }

    func testACancelEndsTheRun() async {
        let (exit, heard) = await call(.init(word: "echo", input: .object(["text": .string("late"), "delay": .number(5)])), cancelAfter: 0.2)
        XCTAssertEqual(exit, .cancelled)
        XCTAssertEqual(heard.last, .failed("cancelled"))
    }
}
