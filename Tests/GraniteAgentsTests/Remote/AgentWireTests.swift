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
            .perform(.init(word: "echo", input: .object(["text": .string("hi"), "times": .integer(2)]), directory: "/p", ask: "say hi",
                           attachments: ["/captures/beach.png"], support: "/support/Echo", model: true)),
            .note("working"),
            .model(.init(id: 1, kind: .object, schema: .object(["type": .string("object")]), system: "s", user: "u", maxTokens: 16, seconds: 5)),
            .answer(.init(id: 1, object: .object(["n": .integer(3)]))),
            .answer(.init(id: 2, error: "no model")),
            .agent(.init(id: 1, word: "veil", input: .object(["action": .string("seal")]))),
            .called(.init(id: 1, output: .object(["id": .string("c1f8")]))),
            .called(.init(id: 2, failed: "no picture", refused: AgentRefusal(.input, "no picture"))),
            .output(.object(["said": .string("hi"), "ratio": .number(0.5), "none": .null, "list": .array([.bool(true)])])),
            .failed("it broke"),
            .cancel,
            .entries([AgentWire.Entry(.package(AnyAgentPackage(EchoPackage.self)))]),
        ]
        XCTAssertEqual(messages.map(\.kind), AgentWire.kinds.filter { $0 != "answer" }.flatMap {
            $0 == "model" ? ["model", "answer", "answer"] : $0 == "called" ? ["called", "called"] : [$0]
        })
        for message in messages {
            let line = try message.line()
            XCTAssertEqual(line.last, 0x0A)
            XCTAssertEqual(line.filter { $0 == 0x0A }.count, 1, "one line: \(message.kind)")
            XCTAssertEqual(try AgentWire.read(line.dropLast()), message)
        }
        XCTAssertEqual(String(decoding: try AgentWire.hello(.init(pid: 7)).line(), as: UTF8.self), #"{"hello":{"pid":7,"wire":"granite-agent/1"}}"# + "\n")
    }

    /// What a host hands a call beside its input is sent only when it hands something, so a call without it is the
    /// line it always was, byte for byte.
    func testAttachmentsAndTheSupportFolderAreSentOnlyWhenOffered() throws {
        let bare = AgentWire.perform(.init(word: "echo", input: .object(["text": .string("hi")]), directory: "/p", model: false))
        XCTAssertEqual(String(decoding: try bare.line(), as: UTF8.self),
                       #"{"perform":{"directory":"/p","input":{"text":"hi"},"model":false,"word":"echo"}}"# + "\n")
        let offered = AgentWire.perform(.init(word: "echo", input: .object([:]), attachments: ["/c/a.png"], support: "/s/Echo"))
        let text = String(decoding: try offered.line(), as: UTF8.self)
        XCTAssertTrue(text.contains(#""attachments":["/c/a.png"]"#), text)
        XCTAssertTrue(text.contains(#""support":"/s/Echo""#), text)
        guard case .perform(let read) = try AgentWire.read(Data(#"{"perform":{"word":"echo","input":{},"model":false}}"#.utf8)) else { return XCTFail() }
        XCTAssertNil(read.attachments, "a host from before them reads as offering none")
        XCTAssertNil(read.support)
        XCTAssertNil(read.agents, "and no agents")
        let calling = AgentWire.perform(.init(word: "needy", input: .object([:]), agents: ["veil"]))
        XCTAssertTrue(String(decoding: try calling.line(), as: UTF8.self).contains(#""agents":["veil"]"#))
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
        XCTAssertNil(entry.takes, "a package that reads no file of the person's says nothing of it")
        XCTAssertNil(entry.keeps)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(entry), as: UTF8.self).contains("takes"))
        let read = try JSONDecoder().decode(AgentWire.Entry.self, from: try JSONEncoder().encode(entry))
        XCTAssertEqual(read, entry)
        guard case .package(let described) = read.rosterEntry(perform: { _, _ in Data("\"remote\"".utf8) }) else { return XCTFail() }
        XCTAssertEqual(described.word, "echo")
        XCTAssertTrue(described.takesDirectory, "the schema came along")
        let hosted = AgentWire.Entry(.package(AnyAgentPackage(HostedPackage.self)))
        XCTAssertEqual(hosted.takes, ["public.image"])
        XCTAssertEqual(hosted.keeps, HostedPackage.keeps)
        let hostedRead = try JSONDecoder().decode(AgentWire.Entry.self, from: try JSONEncoder().encode(hosted))
        guard case .package(let hostedDescribed) = hostedRead.rosterEntry(perform: { _, _ in Data() }) else { return XCTFail() }
        XCTAssertEqual(hostedDescribed.takes, ["public.image"], "what it takes crosses a description")
        XCTAssertEqual(hostedDescribed.keeps, HostedPackage.keeps)
        XCTAssertNil(entry.needs, "a package that needs no agent says nothing of it")
        let needy = AgentWire.Entry(.package(AnyAgentPackage(NeedyPackage.self)))
        XCTAssertEqual(needy.needs, NeedyPackage.needs)
        let needyRead = try JSONDecoder().decode(AgentWire.Entry.self, from: try JSONEncoder().encode(needy))
        guard case .package(let needyDescribed) = needyRead.rosterEntry(perform: { _, _ in Data() }) else { return XCTFail() }
        XCTAssertEqual(needyDescribed.needs, NeedyPackage.needs, "what it needs crosses a description")
        let worker = AgentWire.Entry(.worker(AnyWorkerSpec(ScoutWorker.self)))
        XCTAssertEqual(worker.kind, .worker)
        guard case .worker(let spec) = worker.rosterEntry(perform: { _, _ in Data() }) else { return XCTFail() }
        XCTAssertEqual(spec.word, "scout")
        XCTAssertNil(spec.opening(word: "scout", project: "p"), "a described worker opens as its host does")
    }
}
