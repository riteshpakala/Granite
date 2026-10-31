import Foundation
import XCTest
@testable import GraniteAgents

/// A package installed from source, end to end: read, wrapped, built, described, installed, called and removed.
/// `GRANITE_AGENT_BUILD=1` runs it: it builds Granite in release, which takes minutes.
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
        XCTAssertTrue(Set(stages.all).isSuperset(of: ["reading the package", "building HelloAgent", "asking HelloAgent what it carries"]), "\(stages.all)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".builds").path)
                       && !((try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(".builds").path)) ?? []).isEmpty,
                       "the work folder is gone")

        let notes = Lines()
        let hello = try XCTUnwrap(GraniteRoster(installer.shelf.entries()).package("hello"))
        let output = try await hello.perform(Data(#"{"name": "Rao"}"#.utf8), host: AgentHost(note: { notes.add($0) }))
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: output), "hello, Rao")
        XCTAssertEqual(notes.all.first, "greeting Rao")

        let again = try await installer.install(.path(fixture.path))
        XCTAssertEqual(installer.shelf.installations().map(\.name), ["HelloAgent"], "installing again replaces it whole")
        XCTAssertEqual(again.words, ["hello"])
        try installer.remove("hello")
        XCTAssertEqual(installer.shelf.installations(), [])
    }
}
