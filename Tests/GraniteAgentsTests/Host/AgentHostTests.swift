import Foundation
import XCTest
@testable import GraniteAgents

/// What an app offers a package run beside its JSON reaches the run through `context.host`: the folder, the
/// person's ask, a note the app shows, and the model it has loaded. Without a host a package still runs, and a
/// package that needs the model says whose run went without.
@MainActor
final class AgentHostTests: XCTestCase {
    private func call(_ json: String, host: AgentHost = .none) async throws -> HostedPackage.Answer {
        let data = try await AnyAgentPackage(HostedPackage.self).perform(Data(json.utf8), host: host)
        return try JSONDecoder().decode(HostedPackage.Answer.self, from: data)
    }

    func testAPackageReadsWhatTheHostOffers() async throws {
        let notes = NoteBox()
        let answer = try await call(#"{"directory": "/work"}"#,
                                    host: AgentHost(directory: "/work", ask: "draw the flow", attachments: ["/captures/beach.png"],
                                                    support: "/support/Hosted", note: { notes.append($0) }))
        XCTAssertEqual(answer.ask, "draw the flow")
        XCTAssertEqual(answer.hostDirectory, "/work")
        XCTAssertEqual(answer.directory, "/work", "the input's own field is still the input's")
        XCTAssertEqual(answer.attachments, ["/captures/beach.png"], "the person's file rode the host, not the input")
        XCTAssertEqual(answer.support, "/support/Hosted", "the folder is the host's to place")
        XCTAssertEqual(notes.lines, ["working"], "the note reached the host")
    }

    func testWithoutAHostAPackageStillRuns() async throws {
        let data = try await AnyAgentPackage(HostedPackage.self).perform(Data("{}".utf8))
        let answer = try JSONDecoder().decode(HostedPackage.Answer.self, from: data)
        XCTAssertEqual(answer, HostedPackage.Answer(), "a call with JSON alone is offered nothing")
    }

    func testAHostModelAnswersAnObjectThatFitsItsSchema() async throws {
        let model = FakeHostModel(answer: #"{"n": 7}"#)
        let answer = try await call(#"{"needsModel": true}"#, host: AgentHost(model: model))
        XCTAssertEqual(answer.modelSaid, 7)
        let ask = try XCTUnwrap(model.asked.first)
        let schema = try XCTUnwrap(try JSONSerialization.jsonObject(with: ask.schema) as? [String: Any])
        XCTAssertEqual((schema["properties"] as? [String: Any])?.keys.sorted(), ["n"], "the schema was read off what was asked for")
        XCTAssertEqual(schema["required"] as? [String], ["n"])
        XCTAssertEqual(ask.user, "How many?")
    }

    func testAPackageWithoutAModelSaysWhose() async {
        do {
            _ = try await call(#"{"needsModel": true}"#)
            XCTFail("a run that needs the model answered without one")
        } catch {
            XCTAssertTrue("\(error)".contains("hosted asks the host's model"), "\(error)")
        }
    }

    func testAnAnswerThatDoesNotDecodeSaysSo() async {
        do {
            _ = try await call(#"{"needsModel": true}"#, host: AgentHost(model: FakeHostModel(answer: #"{"n": "seven"}"#)))
            XCTFail("an answer of the wrong shape was taken")
        } catch {
            XCTAssertTrue("\(error)".contains("does not decode"), "\(error)")
        }
    }

    func testAChildInheritsTheHost() async throws {
        let answer = try await call(#"{"spawn": true}"#, host: AgentHost(ask: "the person's words"))
        XCTAssertEqual(answer.childAsk, "the person's words")
    }

    func testTheGuideIsThePackagesOwn() throws {
        XCTAssertEqual(AnyAgentPackage(EchoPackage.self).guide, "", "a package that says nothing has no guide")
        let hosted = try XCTUnwrap(GraniteRoster.discovered().package("hosted"), "the record is in this test binary")
        XCTAssertEqual(hosted.guide, HostedPackage.guide)
    }

    /// What a package reads of the person's files and what it keeps are its own declarations: one that says nothing
    /// takes no file and is placed no folder.
    func testWhatAPackageTakesAndKeepsIsItsOwn() throws {
        let echo = AnyAgentPackage(EchoPackage.self)
        XCTAssertEqual(echo.takes, [], "a package that declares nothing is handed no file of the person's")
        XCTAssertNil(echo.keeps, "and asks for no folder")
        let hosted = try XCTUnwrap(GraniteRoster.discovered().package("hosted"))
        XCTAssertEqual(hosted.takes, ["public.image"])
        XCTAssertEqual(hosted.keeps, HostedPackage.keeps)
    }

    /// A package calls the agents it needs through its host, and only those: the host's other words are not its to see,
    /// a word it never declared is its own fault, never sent, and an agent the host cannot call is the host's refusal.
    func testAPackageCallsOnlyTheAgentsItNeeds() async throws {
        let agents = TableAgents([
            "echo": { data in
                guard case .object(let call)? = AgentJSON(data: data), case .string(let text)? = call["text"] else { return Data() }
                return try JSONEncoder().encode("\(text) twice")
            },
            "hosted": { _ in Data("\"never\"".utf8) },
        ])
        let needy = AnyAgentPackage(NeedyPackage.self)
        XCTAssertEqual(needy.needs, NeedyPackage.needs)
        let data = try await needy.perform(Data(#"{"word": "echo", "text": "hi"}"#.utf8), host: AgentHost(agents: agents))
        let answer = try JSONDecoder().decode(NeedyPackage.Answer.self, from: data)
        XCTAssertEqual(answer.heard, "hi twice")
        XCTAssertEqual(answer.words, ["echo"], "the run sees only the words its package needs")

        do {
            _ = try await needy.perform(Data(#"{"word": "hosted", "text": "hi"}"#.utf8), host: AgentHost(agents: agents))
            XCTFail("hosted is not a need")
        } catch AgentHostError.undeclared(let word, let caller) {
            XCTAssertEqual(word, "hosted")
            XCTAssertEqual(caller, "needy")
            XCTAssertNil(AgentRefusal.of(AgentHostError.undeclared(word: word, caller: caller)), "its own fault, not a refusal")
        }
        XCTAssertEqual(agents.called, ["echo"], "the undeclared word never reached the host")

        do {
            _ = try await needy.perform(Data(#"{"word": "echo", "text": "hi"}"#.utf8), host: .none)
            XCTFail("this host calls no agents")
        } catch AgentPackageError.refused(_, let refusal, _) {
            XCTAssertEqual(refusal.kind, .host, "a host that cannot call a need refuses as the host")
            XCTAssertTrue(refusal.reasons[0].contains("install `echo`"), refusal.reasons[0])
        }
    }

    /// What the needed agent refuses comes back as the host's refusal, its own kind and words inside: the caller's call
    /// was not what was wrong.
    func testANeededAgentsRefusalIsTheHosts() async throws {
        let agents = TableAgents(["echo": { _ in throw AgentHostError.agent(word: "echo", refusal: AgentRefusal(.input, "no picture"), message: "no picture") }])
        do {
            _ = try await AnyAgentPackage(NeedyPackage.self).perform(Data(#"{"word": "echo", "text": "hi"}"#.utf8), host: AgentHost(agents: agents))
            XCTFail("echo refused")
        } catch AgentPackageError.refused(_, let refusal, let said) {
            XCTAssertEqual(refusal.kind, .host)
            XCTAssertTrue(said.contains("`echo` refused (input): no picture"), said)
        }
    }
}
