import Foundation
import XCTest
@testable import GraniteAgents

/// A package installed from source, end to end: read, wrapped, built, described, installed, called, rebuilt and
/// removed. `GRANITE_AGENT_BUILD=1` runs it: it builds Granite in release, twice, which takes minutes. What a rebuild
/// checks out, and what a runner's `Package.resolved` says, are rows that build nothing.
final class AgentInstallerTests: XCTestCase {
    private final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var kept: [String] = []
        func add(_ line: String) { lock.withLock { kept.append(line) } }
        var all: [String] { lock.withLock { kept } }
    }

    func testAPackageIsInstalledFromSourceAndRuns() async throws {
        guard ProcessInfo.processInfo.environment["GRANITE_AGENT_BUILD"] == "1" else { throw XCTSkip("set GRANITE_AGENT_BUILD=1 to build a runner") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/AgentPackageFixture")
        let stages = Lines()
        let installer = AgentInstaller(folder: folder)
        let installed = try await installer.install(.path(fixture.path), progress: { stages.add($0.stage) })
        XCTAssertEqual(installed.name, "HelloAgent")
        XCTAssertEqual(installed.words, ["hello"])
        XCTAssertEqual(installed.format, AgentInstallation.format)
        XCTAssertEqual(installed.sha256.count, 64)
        XCTAssertNil(installed.granite, "Granite is a folder here, and a folder is not pinned")
        XCTAssertNil(installed.dependencies?["granite"])
        XCTAssertTrue(Set(stages.all).isSuperset(of: ["reading the package", "building HelloAgent", "asking HelloAgent what it carries"]), "\(stages.all)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".builds").path)
                       && !((try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(".builds").path)) ?? []).isEmpty,
                       "the work folder is gone")

        let notes = Lines()
        let hello = try XCTUnwrap(GraniteRoster(installer.shelf.entries()).package("hello"))
        let output = try await hello.perform(Data(#"{"name": "Rao"}"#.utf8), host: AgentHost(note: { notes.add($0) }))
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: output), "hello, Rao")
        XCTAssertEqual(notes.all.first, "greeting Rao")

        let rebuilt = try await installer.rebuild("hello")
        XCTAssertEqual(installer.shelf.installations().map(\.name), ["HelloAgent"], "rebuilding installs again, and replaces it whole")
        XCTAssertEqual(installer.shelf.installation("hello"), rebuilt)
        XCTAssertEqual(rebuilt.source, installed.source, "the record keeps its source")
        XCTAssertEqual(rebuilt.revision, installed.revision, "built from the same commit")
        XCTAssertEqual(rebuilt.words, ["hello"])
        try installer.remove("hello")
        XCTAssertEqual(installer.shelf.installations(), [])
    }

    func testARebuildChecksOutWhatWasBuilt() async throws {
        func installed(_ source: AgentSource, _ revision: String?) -> AgentInstallation {
            AgentInstallation(name: "n", source: source, revision: revision, granite: nil, sha256: "s", size: 1, modified: nil, builtAt: "b", entries: [])
        }
        let rows: [(installed: AgentInstallation, pin: String?, why: String)] = [
            (installed(.git(url: "u", revision: nil), "abc"), "abc", "a head, held at the commit it was"),
            (installed(.git(url: "u", revision: "v1.2"), "abc"), "abc", "the commit, not the tag that may move"),
            (installed(.git(url: "u", revision: "v1.2"), nil), "v1.2", "no commit recorded: what the source asks for"),
            (installed(.git(url: "u", revision: nil), nil), nil, "nothing to hold: the head"),
            (installed(.path("/p"), "abc"), nil, "a folder, as it is"),
            (installed(.delivered(id: "x"), "abc"), nil, "a listing, at what its store pins now"),
        ]
        for row in rows { XCTAssertEqual(AgentInstaller.pin(row.installed), row.pin, row.why) }

        let runner = FileManager.default.temporaryDirectory.appendingPathComponent("agent-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: runner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: runner) }
        XCTAssertNil(AgentInstaller.dependencies(runner), "no Package.resolved: every dependency a folder")
        let resolved = runner.appendingPathComponent("Package.resolved")
        try Data(#"{"originHash": "o", "pins": [], "version": 3}"#.utf8).write(to: resolved)
        XCTAssertNil(AgentInstaller.dependencies(runner), "no pins")
        try Data("""
            {"originHash": "o", "version": 3, "pins": [
              {"identity": "granite", "kind": "remoteSourceControl", "location": "https://github.com/riteshpakala/Granite.git",
               "state": {"branch": "main", "revision": "35f7d7d"}},
              {"identity": "veilgarde", "kind": "remoteSourceControl", "location": "https://example.com/veilgarde.git",
               "state": {"revision": "8f6a3a7", "version": "1.2.0"}},
              {"identity": "unpinned", "kind": "remoteSourceControl", "location": "https://example.com/unpinned.git", "state": {}}
            ]}
            """.utf8).write(to: resolved)
        XCTAssertEqual(AgentInstaller.dependencies(runner), ["granite": "35f7d7d", "veilgarde": "8f6a3a7"],
                       "each pin at its commit, a branch's or a version's alike; a pin without one is not said")

        do {
            _ = try await AgentInstaller(folder: runner).rebuild("nothing")
            XCTFail("rebuilt what is not installed")
        } catch AgentInstallError.notInstalled(let name) {
            XCTAssertEqual(name, "nothing")
        }
    }
}
