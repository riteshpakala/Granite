import Foundation
import XCTest
@testable import GraniteAgents

/// An agent in a process of its own, for one call: described without being made, called with its notes and
/// asks served from the host, failing and crashing with a sentence, cancelled and gone, and measured.
final class AgentProcessTests: XCTestCase {
    /// The runner fixture this test target builds beside it.
    static var runner: URL {
        let beside = Bundle(for: AgentProcessTests.self).bundleURL.deletingLastPathComponent().appendingPathComponent("AgentRunnerFixture")
        if FileManager.default.isExecutableFile(atPath: beside.path) { return beside }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return root.appendingPathComponent(".build/debug/AgentRunnerFixture")
    }

    private final class Notes: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func add(_ line: String) { lock.withLock { lines.append(line) } }
        var all: [String] { lock.withLock { lines } }
    }

    private final class Spent: @unchecked Sendable {
        private let lock = NSLock()
        private var kept: AgentProcessCost?
        func set(_ cost: AgentProcessCost) { lock.withLock { kept = cost } }
        var cost: AgentProcessCost? { lock.withLock { kept } }
    }

    private func said(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTheRunnerSaysWhatItCarriesWithoutMakingIt() async throws {
        let entries = try await AgentProcess(executable: Self.runner).describe()
        XCTAssertEqual(entries.map(\.word), ["parrot"])
        XCTAssertEqual(entries.first?.module, "AgentRunnerFixture")
        XCTAssertEqual(entries.first?.schema?.fields.map(\.name), ["text", "notes", "askModel", "delay", "crash", "fail", "directory"],
                       "the schema crossed in its own order")
        XCTAssertEqual(entries.first?.guide, "Give it text; it says it back.")
    }

    func testOneCallInAProcessOfItsOwn() async throws {
        let notes = Notes(), spent = Spent()
        let folder = FileManager.default.temporaryDirectory
        let host = AgentHost(directory: folder.path, ask: "say it", model: FakeHostModel(answer: #"{"n": 4}"#), note: { notes.add($0) })
        let output = try await AgentProcess(executable: Self.runner).perform(
            word: "parrot", input: Data(#"{"text": "hi", "notes": 2, "askModel": true}"#.utf8), host: host, cost: { spent.set($0) })
        let answer = try said(output)
        XCTAssertEqual(answer["said"] as? String, "hi")
        XCTAssertEqual(answer["modelSaid"] as? Int, 4, "the runner asked this host's model across the pipe")
        XCTAssertEqual(answer["ask"] as? String, "say it")
        XCTAssertEqual(answer["hostDirectory"] as? String, folder.path)
        let pid = try XCTUnwrap(answer["pid"] as? Int)
        XCTAssertNotEqual(Int32(pid), getpid(), "it ran in a process of its own")
        XCTAssertEqual(kill(pid_t(pid), 0), -1, "and the process is gone")
        XCTAssertEqual(notes.all, ["note 1", "note 2"])
        let cost = try XCTUnwrap(spent.cost)
        XCTAssertEqual(cost.status, "exit 0")
        XCTAssertGreaterThan(cost.peakBytes, 1_000_000)
        XCTAssertTrue(cost.sentence.hasPrefix("released · peak "), cost.sentence)
    }

    func testAFailureIsTheAgentsSentence() async throws {
        do {
            _ = try await AgentProcess(executable: Self.runner).perform(word: "parrot", input: Data(#"{"text": "x", "fail": true}"#.utf8), host: .none)
            XCTFail("it was told to fail")
        } catch AgentRemoteError.failed(let word, let message) {
            XCTAssertEqual(word, "parrot")
            XCTAssertTrue(message.contains("told to fail"), message)
        }
    }

    func testACrashEndsTheCallWithHowItEnded() async throws {
        do {
            _ = try await AgentProcess(executable: Self.runner).perform(word: "parrot", input: Data(#"{"text": "x", "crash": true}"#.utf8), host: .none)
            XCTFail("it was told to crash")
        } catch AgentRemoteError.ended(let word, let status, let log) {
            XCTAssertEqual(word, "parrot")
            XCTAssertEqual(status, "signal 6", "abort()")
            XCTAssertTrue(log.contains("this line must not reach the wire"), "the end of its stderr: \(log)")
        }
    }

    func testCancellingTheCallEndsTheProcess() async throws {
        let notes = Notes()
        let call = Task {
            try await AgentProcess(executable: Self.runner).perform(word: "parrot", input: Data(#"{"text": "x", "delay": 30}"#.utf8),
                                                                    host: AgentHost(note: { notes.add($0) }))
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        let started = Date()
        call.cancel()
        do {
            _ = try await call.value
            XCTFail("it was cancelled")
        } catch is CancellationError {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "a cancel does not wait out the run")
    }

    func testARosterEntryCallsAProcessAndChecksFirst() async throws {
        let entries = try await AgentProcess(executable: Self.runner).describe()
        let roster = GraniteRoster(RemoteAgent.entries(entries, executable: Self.runner))
        let parrot = try XCTUnwrap(roster.package("parrot"))
        XCTAssertEqual(parrot.summary, "says its text back, in a process of its own.")
        let notes = Notes()
        let output = try await parrot.perform(Data(#"{"text": "via the roster"}"#.utf8), host: AgentHost(note: { notes.add($0) }))
        XCTAssertEqual(try said(output)["said"] as? String, "via the roster")
        XCTAssertTrue(notes.all.last?.hasPrefix("released · peak ") == true, "the host hears what the process took: \(notes.all)")
        struct Changed: Error {}
        let refused = GraniteRoster(RemoteAgent.entries(entries, executable: Self.runner, check: { throw Changed() }))
        do {
            _ = try await refused.package("parrot")!.perform(Data(#"{"text": "x"}"#.utf8))
            XCTFail("the check refused it")
        } catch is Changed {}
    }
}
