import Foundation
import XCTest
@testable import GraniteAgents

/// The wire's messages and an agent's description read back exactly as they were written, schema included.
final class AgentWireTests: XCTestCase {
    func testASchemaReadsBackWithItsOrderAndItsAny() throws {
        let schema = GraniteSchema.object([
            .init(name: "zeta", schema: .string, required: true),
            .init(name: "alpha", schema: .array(.choice(["a", "b"])), required: false),
            .init(name: "nested", schema: .object([.init(name: "n", schema: .integer, required: true)]), required: false),
            .init(name: "loose", schema: .any, required: false),
            .init(name: "ratio", schema: .number, required: false),
            .init(name: "on", schema: .boolean, required: false),
        ])
        let data = try JSONEncoder().encode(schema)
        XCTAssertEqual(try JSONDecoder().decode(GraniteSchema.self, from: data), schema)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""schema":"any""#), "`.any` is said as itself")
        XCTAssertEqual(GraniteSchema.of(EchoPackage.Input.self), try JSONDecoder().decode(GraniteSchema.self, from: try JSONEncoder().encode(GraniteSchema.of(EchoPackage.Input.self))))
    }

    func testEveryMessageIsOneLineThatReadsBack() throws {
        let messages: [AgentWire] = [
            .hello(.init(pid: 42)),
            .perform(.init(word: "echo", input: .object(["text": .string("hi"), "times": .integer(2)]), directory: "/p", ask: "say hi", model: true)),
            .note("working"),
            .model(.init(id: 1, kind: .object, schema: .object(["type": .string("object")]), system: "s", user: "u", maxTokens: 16, seconds: 5)),
            .answer(.init(id: 1, object: .object(["n": .integer(3)]))),
            .answer(.init(id: 2, error: "no model")),
            .output(.object(["said": .string("hi"), "ratio": .number(0.5), "none": .null, "list": .array([.bool(true)])])),
            .failed("it broke"),
            .cancel,
            .entries([AgentWire.Entry(.package(AnyAgentPackage(EchoPackage.self)))]),
        ]
        XCTAssertEqual(messages.map(\.kind), AgentWire.kinds.filter { $0 != "answer" }.flatMap { $0 == "model" ? ["model", "answer", "answer"] : [$0] })
        for message in messages {
            let line = try message.line()
            XCTAssertEqual(line.last, 0x0A)
            XCTAssertEqual(line.filter { $0 == 0x0A }.count, 1, "one line: \(message.kind)")
            XCTAssertEqual(try AgentWire.read(line.dropLast()), message)
        }
        XCTAssertEqual(String(decoding: try AgentWire.hello(.init(pid: 7)).line(), as: UTF8.self), #"{"hello":{"pid":7,"wire":"granite-agent/1"}}"# + "\n")
    }

    func testAFieldAReaderDoesNotKnowIsIgnoredAndAMessageItDoesNotKnowIsNot() throws {
        XCTAssertEqual(try AgentWire.read(Data(#"{"note":"hi","later":true}"#.utf8)), .note("hi"))
        XCTAssertEqual(try AgentWire.read(Data(#"{"hello":{"wire":"granite-agent/1","since":"later"}}"#.utf8)), .hello(.init()))
        XCTAssertThrowsError(try AgentWire.read(Data(#"{"shout":"hi"}"#.utf8)))
    }

    func testAnEntryDescribesAnAgentWithoutItsType() throws {
        let echo = AnyAgentPackage(EchoPackage.self)
        let entry = AgentWire.Entry(.package(echo))
        XCTAssertEqual(entry.kind, .package)
        XCTAssertEqual(entry.word, "echo")
        XCTAssertEqual(entry.module, "GraniteAgentsTests")
        XCTAssertEqual(entry.schema, echo.schema)
        XCTAssertEqual(entry.fields, EchoPackage.fields)
        XCTAssertNil(entry.guide, "an empty guide is left out")
        let read = try JSONDecoder().decode(AgentWire.Entry.self, from: try JSONEncoder().encode(entry))
        XCTAssertEqual(read, entry)
        guard case .package(let described) = read.rosterEntry(perform: { _, _ in Data("\"remote\"".utf8) }) else { return XCTFail() }
        XCTAssertEqual(described.word, "echo")
        XCTAssertTrue(described.takesDirectory, "the schema came along")
        let worker = AgentWire.Entry(.worker(AnyWorkerSpec(ScoutWorker.self)))
        XCTAssertEqual(worker.kind, .worker)
        guard case .worker(let spec) = worker.rosterEntry(perform: { _, _ in Data() }) else { return XCTFail() }
        XCTAssertEqual(spec.word, "scout")
        XCTAssertNil(spec.opening(word: "scout", project: "p"), "a described worker opens as its host does")
    }
}
