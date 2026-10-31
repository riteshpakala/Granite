import Foundation
import Granite
import XCTest
@testable import GraniteAgents

/// A package agent is found by the record its binary carries, with nothing listed by hand, and a call runs
/// through Granite's own center for it, JSON in and JSON out, each call a run of its own.
@MainActor
final class GraniteRosterTests: XCTestCase {
    func testARecordInTheBinaryIsFoundWithNothingListed() throws {
        let roster = GraniteRoster.discovered()
        let echo = try XCTUnwrap(roster.package("echo"), "the echo's record is in this test binary")
        XCTAssertEqual(echo.module, "GraniteAgentsTests")
        XCTAssertEqual(echo.summary, EchoPackage.summary)
        XCTAssertEqual(roster.workers.map(\.word), ["scout"], "the scout's record, and only the records")
        XCTAssertNil(roster.package("scout"), "a worker spec is no package agent")
    }

    func testTheFirstOfAWordIsKept() {
        let roster = GraniteRoster([.package(AnyAgentPackage(EchoPackage.self)), .package(AnyAgentPackage(EchoTwin.self)),
                                    .worker(AnyWorkerSpec(QuietWorker.self))])
        XCTAssertEqual(roster.entries.map(\.word), ["echo", "quiet"])
        XCTAssertTrue(roster.packages[0].type.hasSuffix("EchoPackage"))
    }

    func testAPackageCallIsJSONInAndJSONOutThroughItsOwnCenter() async throws {
        let echo = AnyAgentPackage(EchoPackage.self)
        let before = AgentPackageHost<EchoPackage>.shared().command.center.state
        let answer = try await echo.perform(Data(#"{"text":"hi","times":2}"#.utf8))
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: answer), "hi hi")
        let after = AgentPackageHost<EchoPackage>.shared().command.center.state
        XCTAssertEqual(after.runs - before.runs, 1, "the call was one run of the engine")
        XCTAssertEqual(after.finished - before.finished, 1)
        XCTAssertEqual(after.events - before.events, 1, "its event was reduced into the package's center")
        XCTAssertTrue(echo.takesDirectory)
    }

    func testCallsAreRunsOfTheirOwn() async throws {
        let echo = AnyAgentPackage(EchoPackage.self)
        async let first = echo.perform(Data(#"{"text":"a","delay":0.1}"#.utf8))
        async let second = echo.perform(Data(#"{"text":"b","delay":0.1}"#.utf8))
        let (a, b) = try await (first, second)
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: a), "a", "neither took the other's place")
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: b), "b")
    }

    func testCancellingTheCallCancelsTheRun() async throws {
        let echo = AnyAgentPackage(EchoPackage.self)
        let before = AgentPackageHost<EchoPackage>.shared().command.center.state.cancelled
        let call = Task { try await echo.perform(Data(#"{"text":"late","delay":5}"#.utf8)) }
        _ = await until { AgentPackageHost<EchoPackage>.shared().executable.liveKeys().contains { $0.hasPrefix("echo-") } }
        call.cancel()
        do { _ = try await call.value; XCTFail("a cancelled call answered") } catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        let cancelled = await until { AgentPackageHost<EchoPackage>.shared().command.center.state.cancelled == before + 1 }
        XCTAssertTrue(cancelled, "the run the call started was cancelled with it")
    }

    func testAnInputThatDoesNotDecodeSaysWhose() async {
        do {
            _ = try await AnyAgentPackage(EchoPackage.self).perform(Data(#"{"times":2}"#.utf8))
            XCTFail("a call without its text answered")
        } catch let error as AgentPackageError {
            guard case .input(let word, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(word, "echo")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testAWorkerSpecSaysItsWordsAndLeavesTheRestToTheApp() {
        let scout = AnyWorkerSpec(ScoutWorker.self)
        XCTAssertEqual(scout.toolNames, ["read_file", "list_files"])
        XCTAssertEqual(scout.budget, .shell)
        XCTAssertTrue(scout.shell)
        XCTAssertEqual(scout.opening(word: "scout", project: "/p"), "You are a scout, mapping /p.")
        XCTAssertEqual(scout.reportRule, "List every file with one line.")
        let quiet = AnyWorkerSpec(QuietWorker.self)
        XCTAssertEqual(quiet.toolNames, [], "the app's reading set")
        XCTAssertEqual(quiet.budget, .reading)
        XCTAssertFalse(quiet.shell)
        XCTAssertNil(quiet.opening(word: "quiet", project: "/p"))
        XCTAssertNil(quiet.reportRule)
    }
}
