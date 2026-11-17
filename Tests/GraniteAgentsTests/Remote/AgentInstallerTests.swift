import Foundation
import XCTest
@testable import GraniteAgents

/// A package installed from source, end to end: read, wrapped, built, described, finished, installed, called, refused
/// a rebuild by a finisher, rebuilt and removed. `GRANITE_AGENT_BUILD=1` runs it: it builds Granite in release three
/// times, which takes minutes. What a rebuild checks out, what a runner's `Package.resolved` says, and what a finisher
/// of either form is handed, are rows that build nothing.
final class AgentInstallerTests: XCTestCase {
    private final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var kept: [String] = []
        func add(_ line: String) { lock.withLock { kept.append(line) } }
        var all: [String] { lock.withLock { kept } }
    }

    /// Writes down, beside the executable, the name and which of what it was handed is where it says.
    private struct Recording: AgentBuildFinishing {
        func finish(_ build: AgentBuild) async throws {
            build.say("writing down the build")
            let manager = FileManager.default
            let found = [("staged agent", manager.isExecutableFile(atPath: build.executable.path)),
                         ("products", manager.fileExists(atPath: build.products.appendingPathComponent("agent").path)),
                         ("runner", manager.fileExists(atPath: build.runner.appendingPathComponent("Sources/agent/Agent.swift").path)),
                         ("package", manager.fileExists(atPath: build.package.appendingPathComponent("Package.swift").path))]
            try "\(build.name): \(found.filter(\.1).map(\.0).joined(separator: ", "))"
                .write(to: build.staged.appendingPathComponent("finished.txt"), atomically: true, encoding: .utf8)
        }
    }

    private struct Refusing: AgentBuildFinishing {
        struct Refused: Error {}
        func finish(_ build: AgentBuild) async throws { throw Refused() }
    }

    func testAPackageIsInstalledFromSourceAndRuns() async throws {
        guard ProcessInfo.processInfo.environment["GRANITE_AGENT_BUILD"] == "1" else { throw XCTSkip("set GRANITE_AGENT_BUILD=1 to build a runner") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/AgentPackageFixture")
        let stages = Lines(), said = Lines()
        let installer = AgentInstaller(folder: folder, finishers: [Recording()])
        let installed = try await installer.install(.path(fixture.path), progress: { step in
            stages.add(step.stage)
            if let line = step.line, step.stage.hasPrefix("finishing") { said.add("\(step.stage): \(line)") }
        })
        XCTAssertEqual(installed.name, "HelloAgent")
        XCTAssertEqual(installed.words, ["hello"])
        XCTAssertEqual(installed.format, AgentInstallation.format)
        XCTAssertEqual(installed.sha256.count, 64)
        XCTAssertNil(installed.granite, "Granite is a folder here, and a folder is not pinned")
        XCTAssertNil(installed.dependencies?["granite"])
        XCTAssertTrue(Set(stages.all).isSuperset(of: ["reading the package", "building HelloAgent", "asking HelloAgent what it carries"]), "\(stages.all)")
        let order = stages.all.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }
        XCTAssertEqual(Array(order.suffix(3)), ["finishing HelloAgent", "installing HelloAgent", "installed HelloAgent: hello"], "\(order)")
        XCTAssertEqual(said.all, ["finishing HelloAgent: writing down the build"])
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("HelloAgent/finished.txt"), encoding: .utf8),
                       "HelloAgent: staged agent, products, runner, package", "what a finisher puts beside the executable lands with it")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".builds").path)
                       && !((try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(".builds").path)) ?? []).isEmpty,
                       "the work folder is gone")

        let notes = Lines()
        let hello = try XCTUnwrap(GraniteRoster(installer.shelf.entries()).package("hello"))
        let output = try await hello.perform(Data(#"{"name": "Rao"}"#.utf8), host: AgentHost(note: { notes.add($0) }))
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: output), "hello, Rao")
        XCTAssertEqual(notes.all.first, "greeting Rao")

        do {
            _ = try await AgentInstaller(folder: folder, finishers: [Refusing()]).rebuild("hello")
            XCTFail("a finisher refused the build")
        } catch is Refusing.Refused {
            XCTAssertEqual(installer.shelf.installation("hello"), installed, "a finisher that throws leaves the installation as it was")
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".HelloAgent.new").path), "and nothing staged")
        }

        let again = Lines()
        let rebuilt = try await installer.rebuild("hello") { again.add($0.stage) }
        XCTAssertEqual(again.all.last, "rebuilt HelloAgent: hello", "a rebuild says so to the end: \(again.all)")
        XCTAssertEqual(installer.shelf.installations().map(\.name), ["HelloAgent"], "rebuilding installs again, and replaces it whole")
        XCTAssertEqual(installer.shelf.installation("hello"), rebuilt)
        XCTAssertEqual(rebuilt.source, installed.source, "the record keeps its source")
        XCTAssertEqual(rebuilt.revision, installed.revision, "built from the same commit")
        XCTAssertEqual(rebuilt.words, ["hello"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("HelloAgent/finished.txt").path), "finished again")
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

    func testAFinisherOfEitherFormIsHandedTheBuild() async throws {
        struct Older: AgentBuildFinishing {
            let heard: Lines
            func finish(_ executable: URL, name: String) async throws { heard.add("\(name) \(executable.path)") }
        }
        struct Newer: AgentBuildFinishing {
            func finish(_ build: AgentBuild) async throws { build.say("\(build.name) in \(build.staged.path)") }
        }
        let heard = Lines(), said = Lines()
        let build = AgentBuild(name: "N", executable: URL(fileURLWithPath: "/shelf/.N.new/agent"), runner: URL(fileURLWithPath: "/work/runner"),
                               products: URL(fileURLWithPath: "/work/runner/.build/release"), package: URL(fileURLWithPath: "/work/N"),
                               say: { said.add($0) })
        try await Older(heard: heard).finish(build)
        XCTAssertEqual(heard.all, ["N /shelf/.N.new/agent"], "a finisher of the older form is handed what it always was")
        try await Newer().finish(build)
        try await Newer().finish(URL(fileURLWithPath: "/x/agent"), name: "x")
        XCTAssertEqual(said.all, ["N in /shelf/.N.new"], "the newer form says its line; the older form it does not write does nothing")
    }
}
