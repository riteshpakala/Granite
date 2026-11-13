import Foundation
import XCTest
@testable import GraniteAgents

/// A shelf of installed runners: read without running one, offered as a roster, and an executable that changed
/// since it was installed refused before it runs.
final class AgentShelfTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-shelf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    /// The runner fixture, installed by hand as an installer would leave it.
    private func installParrot() async throws -> AgentInstallation {
        let home = folder.appendingPathComponent("Parrot", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let executable = home.appendingPathComponent("agent")
        try FileManager.default.copyItem(at: AgentProcessTests.runner, to: executable)
        let attributes = try FileManager.default.attributesOfItem(atPath: executable.path)
        let installation = AgentInstallation(
            name: "Parrot", source: .path("/somewhere/Parrot"), revision: "abc", granite: "e64723f", sha256: try AgentShelf.sha256(of: executable),
            size: (attributes[.size] as? NSNumber)?.int64Value ?? 0, modified: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970,
            builtAt: "2026-10-31T00:00:00Z", entries: try await AgentProcess(executable: executable).describe())
        try JSONEncoder().encode(installation).write(to: home.appendingPathComponent(AgentInstallation.file))
        return installation
    }

    func testTheShelfOffersWhatIsInstalledWithoutRunningIt() async throws {
        let shelf = AgentShelf(folder: folder)
        XCTAssertEqual(shelf.installations(), [])
        let empty = shelf.stamp
        let installed = try await installParrot()
        XCTAssertNotEqual(shelf.stamp, empty, "a host knows to read the shelf again")
        XCTAssertEqual(shelf.installations(), [installed])
        XCTAssertEqual(shelf.installation("parrot")?.name, "Parrot", "found by the agent it carries")
        XCTAssertEqual(shelf.installation("PARROT")?.name, "Parrot")
        let roster = GraniteRoster(shelf.entries())
        let output = try await XCTUnwrap(roster.package("parrot")).perform(Data(#"{"text": "from the shelf"}"#.utf8))
        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("from the shelf"))
    }

    func testAChangedExecutableIsRefused() async throws {
        _ = try await installParrot()
        let shelf = AgentShelf(folder: folder)
        let handle = try FileHandle(forWritingTo: folder.appendingPathComponent("Parrot/agent"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()
        do {
            _ = try await GraniteRoster(shelf.entries()).package("parrot")!.perform(Data(#"{"text": "x"}"#.utf8))
            XCTFail("a changed executable must not run")
        } catch AgentRemoteError.changed(let word, let path) {
            XCTAssertEqual(word, "parrot")
            XCTAssertTrue(path.hasSuffix("Parrot/agent"))
        }
    }

    func testAFolderWhoseRecordDoesNotReadIsSaidAndLeftOut() throws {
        let broken = folder.appendingPathComponent("Broken", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: broken.appendingPathComponent(AgentInstallation.file))
        let shelf = AgentShelf(folder: folder)
        XCTAssertEqual(shelf.installations(), [])
        XCTAssertEqual(shelf.problems().count, 1)
        XCTAssertTrue(shelf.problems()[0].hasPrefix("Broken:"), shelf.problems()[0])
    }

    func testASourceIsARepositoryAtARevisionOrAFolder() {
        XCTAssertEqual(AgentSource("https://github.com/rao/PlateAgent.git"), .git(url: "https://github.com/rao/PlateAgent.git", revision: nil))
        XCTAssertEqual(AgentSource("https://github.com/rao/PlateAgent.git@f9bdda7"), .git(url: "https://github.com/rao/PlateAgent.git", revision: "f9bdda7"))
        XCTAssertEqual(AgentSource("git@github.com:rao/PlateAgent.git"), .git(url: "git@github.com:rao/PlateAgent.git", revision: nil))
        XCTAssertEqual(AgentSource("git@github.com:rao/PlateAgent.git@main"), .git(url: "git@github.com:rao/PlateAgent.git", revision: "main"))
        XCTAssertEqual(AgentSource("/tmp/x/../Agent"), .path("/tmp/Agent"))
        XCTAssertEqual(AgentSource("./Agent", base: URL(fileURLWithPath: "/work")), .path("/work/Agent"))
        XCTAssertEqual(AgentSource("https://x/y.git@abc").newest, .git(url: "https://x/y.git", revision: nil))
        XCTAssertEqual(AgentSource("https://x/y.git@abc").description, "https://x/y.git@abc")
    }

    func testADeliveredSourceIsKeptByItsListingAlone() throws {
        let source = AgentSource.delivered(id: "49a6cf94-76cb-4ce6-a03e-8c1042081655")
        XCTAssertEqual(source.newest, source, "an update asks the store again")
        XCTAssertEqual(source.description, "delivered:49a6cf94-76cb-4ce6-a03e-8c1042081655")
        let json = try JSONEncoder().encode(source)
        XCTAssertEqual(String(decoding: json, as: UTF8.self), #"{"delivered":"49a6cf94-76cb-4ce6-a03e-8c1042081655"}"#, "no address that expires")
        XCTAssertEqual(try JSONDecoder().decode(AgentSource.self, from: json), source)
        XCTAssertEqual(try JSONDecoder().decode(AgentSource.self, from: Data(#"{"url":"https://x/y.git","revision":"abc"}"#.utf8)),
                       .git(url: "https://x/y.git", revision: "abc"), "an installation from before still reads")
        XCTAssertEqual(try JSONDecoder().decode(AgentSource.self, from: Data(#"{"path":"/tmp/Agent"}"#.utf8)), .path("/tmp/Agent"))
    }
}
