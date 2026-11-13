import Foundation
import XCTest
@testable import GraniteAgents

/// A store's listing fetched as the installer fetches it, short of the build: asked for, downloaded, checked, decoded
/// and unpacked into the work folder, under the name the store gives it.
final class AgentDeliveredTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-delivered-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    private struct Store: AgentDeliverer {
        let delivery: AgentDelivery
        let asked = Asked()
        func delivery(for id: String, accepts: [String]) async throws -> AgentDelivery {
            asked.add(id: id, accepts: accepts)
            return delivery
        }
    }

    private final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var said: [(String, [String])] = []
        func add(id: String, accepts: [String]) { lock.withLock { said.append((id, accepts)) } }
        var all: [(String, [String])] { lock.withLock { said } }
    }

    /// Reverses the bytes of the file: a stand-in for a real encoding.
    private struct Reversed: AgentPayloadDecoder {
        let transform = "reverse-1"
        func decode(_ file: URL, in work: URL) async throws -> URL {
            let out = work.appendingPathComponent("decoded")
            try Data(try Data(contentsOf: file).reversed()).write(to: out)
            return out
        }
    }

    /// A package folder tarred as GitHub archives a repository: one folder inside, named for the owner, repo and commit.
    private func archive(top: String? = "rao-craft-WebAgent-4c38be8") throws -> URL {
        let staging = folder.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        let root = top.map { staging.appendingPathComponent($0, isDirectory: true) } ?? staging
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources/WebAgent"), withIntermediateDirectories: true)
        try "// swift-tools-version:6.0\n".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "struct Web {}\n".write(to: root.appendingPathComponent("Sources/WebAgent/Web.swift"), atomically: true, encoding: .utf8)
        let out = folder.appendingPathComponent("archive-\(UUID().uuidString).tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-czf", out.path, "-C", staging.path] + (top.map { [$0] } ?? ["Package.swift", "Sources"])
        try tar.run()
        tar.waitUntilExit()
        XCTAssertEqual(tar.terminationStatus, 0)
        return out
    }

    private func work() throws -> URL {
        let work = folder.appendingPathComponent("work-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        return work
    }

    private let id = "49a6cf94-76cb-4ce6-a03e-8c1042081655"
    private let sha = String(repeating: "a", count: 40)

    func testADeliveryIsUnpackedUnderTheNameTheStoreGives() async throws {
        let tarball = try archive()
        let store = Store(delivery: AgentDelivery(revision: sha, directory: "WebAgent", url: tarball, sha256: try AgentShelf.sha256(of: tarball)))
        let work = try work()
        let fetched = try await AgentDelivered.fetch(id, deliverer: store, decoders: [Reversed()], session: .shared, work: work, progress: { _ in })
        XCTAssertEqual(fetched.revision, sha, "the revision is the store's, with no git to ask")
        XCTAssertEqual(fetched.package.lastPathComponent, "WebAgent", "the package's identity, as a clone would give it")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fetched.package.appendingPathComponent("Sources/WebAgent/Web.swift").path))
        XCTAssertTrue(fetched.package.path.hasPrefix(work.path), "the source lives in the work folder alone")
        XCTAssertEqual(store.asked.all.map(\.0), [id])
        XCTAssertEqual(store.asked.all.first?.1, ["reverse-1"], "the store is told what this machine can undo")
    }

    func testAnArchiveWithItsFilesAtTheRootUnpacksToo() async throws {
        let store = Store(delivery: AgentDelivery(revision: sha, directory: "rao-Web-Agent", url: try archive(top: nil)))
        let fetched = try await AgentDelivered.fetch(id, deliverer: store, decoders: [], session: .shared, work: try work(), progress: { _ in })
        XCTAssertEqual(fetched.package.lastPathComponent, "rao-Web-Agent")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fetched.package.appendingPathComponent("Package.swift").path))
    }

    func testATransformIsUndoneBeforeUnpacking() async throws {
        let tarball = try archive()
        let encoded = folder.appendingPathComponent("encoded")
        try Data(try Data(contentsOf: tarball).reversed()).write(to: encoded)
        let store = Store(delivery: AgentDelivery(revision: sha, directory: "WebAgent", url: encoded, transforms: ["reverse-1"]))
        let fetched = try await AgentDelivered.fetch(id, deliverer: store, decoders: [Reversed()], session: .shared, work: try work(), progress: { _ in })
        XCTAssertTrue(FileManager.default.fileExists(atPath: fetched.package.appendingPathComponent("Package.swift").path))
    }

    func testWhatCantBeReadIsRefusedWithAReason() async throws {
        let tarball = try archive()
        let source = AgentSource.delivered(id: id).description
        let unknown = Store(delivery: AgentDelivery(revision: sha, directory: "WebAgent", url: tarball, transforms: ["sealed-9"]))
        await assertRefused(try await AgentDelivered.fetch(id, deliverer: unknown, decoders: [], session: .shared, work: try work(), progress: { _ in }),
                            .delivery(source: source, reason: "it arrives as `sealed-9`, which this version can't read; update the app"))
        let altered = Store(delivery: AgentDelivery(revision: sha, directory: "WebAgent", url: tarball, sha256: String(repeating: "0", count: 64)))
        await assertRefused(try await AgentDelivered.fetch(id, deliverer: altered, decoders: [], session: .shared, work: try work(), progress: { _ in }),
                            .delivery(source: source, reason: "the archive is not the one the store described"))
        await assertRefused(try await AgentDelivered.fetch(id, deliverer: nil, decoders: [], session: .shared, work: try work(), progress: { _ in }),
                            .delivery(source: source, reason: "nothing here can ask its store for it"))
    }

    func testAnEntryThatClimbsOutIsUnsafeAndNamesArePlain() {
        XCTAssertTrue(AgentDelivered.unsafe("/etc/passwd"))
        XCTAssertTrue(AgentDelivered.unsafe("x/../../y"))
        XCTAssertFalse(AgentDelivered.unsafe("rao-craft-WebAgent-4c38be8/Sources/WebAgent/Web.swift"))
        XCTAssertFalse(AgentDelivered.unsafe("a/..b/c"))
        XCTAssertEqual(AgentDelivered.folderName("rao-Web-Agent"), "rao-Web-Agent")
        XCTAssertEqual(AgentDelivered.folderName("../x/y"), "..-x-y")
        XCTAssertEqual(AgentDelivered.folderName(".."), "package")
        XCTAssertEqual(AgentDelivered.folderName(""), "package")
    }

    private func assertRefused<T>(_ work: @autoclosure () async throws -> T, _ expected: AgentInstallError, line: UInt = #line) async {
        do {
            _ = try await work()
            XCTFail("expected \(expected)", line: line)
        } catch let error as AgentInstallError {
            XCTAssertEqual(error, expected, line: line)
        } catch {
            XCTFail("unexpected \(error)", line: line)
        }
    }
}
