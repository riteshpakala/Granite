import Foundation
import XCTest
@testable import GraniteAgents

/// `granite-answer/1`, as rows: a conforming answer checked and stamped; each way it can break the standard refused
/// as kind `answer` with the reason; a thrown refusal keeping its kind past the engine; an answer that does not
/// conform passing as it always did; and the refusal on the wire, read by a reader that knows it and one that does not.
final class AgentAnswerTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("granite-answer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    private func call(_ mode: String) async throws -> [String: AgentJSON] {
        // The input's `directory` is the host's to fill (§6), as Craft fills it.
        let input = #"{"name": "ada", "mode": "\#(mode)", "directory": "\#(folder.path)"}"#
        let data = try await AnyAgentPackage(MakerPackage.self).perform(Data(input.utf8), host: AgentHost(directory: folder.path))
        guard case .object(let object)? = AgentJSON(data: data) else { XCTFail("not an object"); return [:] }
        return object
    }

    func testAConformingAnswerIsCheckedAndStamped() async throws {
        let answer = try await call("good")
        XCTAssertEqual(answer["format"], .string(AgentAnswerStandard.format))
        XCTAssertEqual(answer["agent"], .object(["word": .string("maker")]))
        XCTAssertEqual(answer["card"], .string("ada"), "the package's own keys pass through")
        guard case .array(let made)? = answer["made"], case .object(let first)? = made.first else { return XCTFail("\(answer)") }
        XCTAssertEqual(first["kind"], .string("card"))
        XCTAssertEqual(AnyAgentPackage(MakerPackage.self).makes, MakerPackage.makes)
    }

    func testEachWayToBreakTheStandardIsRefusedAsAnAnswer() async throws {
        let rows: [(mode: String, reason: String)] = [
            ("path", "`path` cards/elsewhere.card.json is not one of `paths`"),
            ("kind", "`made[0]` is a `chart`, and maker makes `card`"),
            ("payload", "`payloads[0]` says `test-card/1`, and the file's own `schema` is `other-card/1`"),
            ("stamp", "`format` is the runner's to say: an answer does not encode it"),
            ("previewStray", "`interactions[0]` is about cards/stray.card.json, which is not one of `paths`"),
        ]
        for row in rows {
            do {
                _ = try await call(row.mode)
                XCTFail("\(row.mode) answered")
            } catch AgentPackageError.refused(let word, let refusal, let said) {
                XCTAssertEqual(word, "maker")
                XCTAssertEqual(refusal.kind, .answer, row.mode)
                XCTAssertTrue(refusal.reasons.contains(row.reason), "\(row.mode): \(refusal.reasons)")
                XCTAssertTrue(said.hasPrefix("maker's answer breaks granite-answer/1"), said)
            }
        }
    }

    /// An answer asks a client to show what it made in words any client reads; the check holds its files to `paths`
    /// and to the disk, and leaves the vocabulary open.
    func testAnInteractionIsCheckedAndPassedOn() async throws {
        let previewed = try await call("preview")
        XCTAssertEqual(previewed["format"], .string(AgentAnswerStandard.format), "stamped")
        XCTAssertEqual(previewed["interactions"], .array([.object(["kind": .string("preview"), "paths": .array([.string("cards/ada.card.json")]),
                                                                   "title": .string("the card of ada")])]))
        let unknown = try await call("unknownKind")
        guard case .array(let asked)? = unknown["interactions"], case .object(let first)? = asked.first else { return XCTFail("\(unknown)") }
        XCTAssertEqual(first["kind"], .string("hologram"), "a kind no client knows yet still passes: a client ignores it")
        XCTAssertEqual(AgentInteraction.preview(["a.png"]), AgentInteraction(kind: AgentInteraction.previewKind, paths: ["a.png"]))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(AgentInteraction.preview(["a.png"])), as: UTF8.self).contains("title"),
                       "a caption left out is not said")
    }

    func testEachWayAnInteractionBreaksTheStandard() throws {
        let written = folder.appendingPathComponent("cards/a.png")
        try FileManager.default.createDirectory(at: written.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: written)
        func interactions(_ value: AgentJSON) -> [String] {
            AgentAnswerCheck.problems(in: ["paths": .array([.string("cards/a.png"), .string("cards/gone.png")]), "interactions": value],
                                      word: "maker", makes: MakerPackage.makes, directory: folder.path)
        }
        func one(_ object: [String: AgentJSON]) -> [String] { interactions(.array([.object(object)])) }
        let rows: [(problems: [String], reason: String)] = [
            (one(["kind": .string("Preview"), "paths": .array([.string("cards/a.png")])]), "`interactions[0].kind` is one lowercase word"),
            (one(["kind": .string("preview"), "paths": .array([])]),
             "`interactions[0]` names no file: its `paths` lists the files it is about, lead first"),
            (one(["kind": .string("preview")]), "`interactions[0]` needs a `kind` and `paths`"),
            (one(["kind": .string("preview"), "paths": .array([.string("cards/a.png"), .string("./cards/a.png")])]),
             "`interactions[0]` names ./cards/a.png twice"),
            (one(["kind": .string("preview"), "paths": .array([.string("cards/gone.png")])]),
             "`interactions[0]` is about cards/gone.png, which is not on disk"),
            (one(["kind": .string("preview"), "paths": .array([.string("cards/a.png")]), "title": .integer(3)]),
             "`interactions[0].title` is a caption: a string"),
            (interactions(.string("preview")), "`interactions` is not a list"),
        ]
        for row in rows { XCTAssertTrue(row.problems.contains(row.reason), "\(row.reason): \(row.problems)") }
        XCTAssertEqual(one(["kind": .string("preview"), "paths": .array([.string(written.path)]), "title": .string("a")]), [],
                       "an absolute path to a written file passes")
    }

    func testAThrownRefusalKeepsItsKindPastTheEngine() async throws {
        do {
            _ = try await call("refuse")
            XCTFail("it was told to refuse")
        } catch AgentPackageError.refused(_, let refusal, let said) {
            XCTAssertEqual(refusal, AgentRefusal(.call, "`name` is empty: give the card a name"))
            XCTAssertEqual(said, "`name` is empty: give the card a name", "the agent's sentence, not the engine's")
        }
    }

    func testAnAnswerThatDoesNotConformPassesAsItDid() async throws {
        let data = try await AnyAgentPackage(EchoPackage.self).perform(Data(#"{"text": "hi"}"#.utf8))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #""hi""#)
    }

    func testPathsAreComparedAsFiles() {
        let absolute = folder.appendingPathComponent("cards/a.json").path
        XCTAssertEqual(AgentAnswerCheck.resolved("cards/a.json", under: folder.path), AgentAnswerCheck.resolved(absolute, under: nil))
        XCTAssertEqual(AgentAnswerCheck.resolved("./cards/../cards/a.json", under: folder.path), AgentAnswerCheck.resolved(absolute, under: "/elsewhere"))
    }

    func testARefusalCrossesTheWireBesideItsSentence() throws {
        let refusal = AgentRefusal(.call, ["`post` is mapped twice", "`Comment` has no `text`"])
        let line = try AgentWire.failed(.init("2 problems with the call", refusal: refusal)).line()
        let text = String(decoding: line, as: UTF8.self)
        XCTAssertTrue(text.contains(#""failed":"2 problems with the call""#), text)
        XCTAssertEqual(try AgentWire.read(line), .failed(.init("2 problems with the call", refusal: refusal)))
        XCTAssertEqual(try AgentWire.read(Data(#"{"failed":"it broke"}"#.utf8)), .failed("it broke"), "a sentence alone reads as before")
        let newer = try AgentWire.read(Data(#"{"failed":"x","refused":{"kind":"weather","reasons":["rain"]}}"#.utf8))
        XCTAssertEqual(newer, .failed(.init("x", refusal: AgentRefusal(.host, "rain"))), "a kind this reader does not know reads as host")
        XCTAssertEqual(refusal.description, "2 problems, so nothing was done:\n- `post` is mapped twice\n- `Comment` has no `text`")
        XCTAssertEqual(AgentRefusal.of(AgentPackageError.input(word: "w", reason: "bad")), AgentRefusal(.input, "bad"))
        XCTAssertEqual(AgentRefusal.of(AgentHostError.noModel(word: "w"))?.kind, .model)
        XCTAssertNil(AgentRefusal.of(CocoaError(.fileNoSuchFile)), "anything else is a fault")
    }

    func testAnEntrySaysWhatItMakes() throws {
        let entry = AgentWire.Entry(.package(AnyAgentPackage(MakerPackage.self)))
        XCTAssertEqual(entry.makes, MakerPackage.makes)
        let read = try JSONDecoder().decode(AgentWire.Entry.self, from: JSONEncoder().encode(entry))
        guard case .package(let package) = read.rosterEntry(perform: { _, _ in Data() }) else { return XCTFail("not a package") }
        XCTAssertEqual(package.makes, MakerPackage.makes)
        XCTAssertNil(AgentWire.Entry(.package(AnyAgentPackage(EchoPackage.self))).makes, "an agent that declares nothing says nothing")
        XCTAssertEqual(try JSONDecoder().decode(AgentProcessCost.self, from: Data(#"{"seconds":1,"cpuSeconds":1,"peakBytes":1,"status":"exit 0"}"#.utf8)).asks,
                       0, "a cost recorded before asks were counted")
    }
}
