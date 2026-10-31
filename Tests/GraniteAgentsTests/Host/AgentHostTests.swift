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
                                    host: AgentHost(directory: "/work", ask: "draw the flow", note: { notes.append($0) }))
        XCTAssertEqual(answer.ask, "draw the flow")
        XCTAssertEqual(answer.hostDirectory, "/work")
        XCTAssertEqual(answer.directory, "/work", "the input's own field is still the input's")
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
}
