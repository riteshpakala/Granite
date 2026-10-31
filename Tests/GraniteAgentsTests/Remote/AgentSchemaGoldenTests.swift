import Foundation
import XCTest
@testable import GraniteAgents

/// The standard (`Schema/GraniteAgent.md`) and its JSON Schema files stay the code's: a file that differs from
/// what the code generates fails, and so does a message, an entry field or an installation field the standard
/// does not name. `GRANITE_UPDATE_GOLDEN=1` rewrites the files.
final class AgentSchemaGoldenTests: XCTestCase {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Schema", isDirectory: true)

    func testTheCommittedSchemasAreTheCodes() throws {
        for (name, data) in AgentSchemaJSON.files.sorted(by: { $0.key < $1.key }) {
            let url = Self.folder.appendingPathComponent(name)
            if ProcessInfo.processInfo.environment["GRANITE_UPDATE_GOLDEN"] == "1" {
                try data.write(to: url)
                continue
            }
            XCTAssertEqual(try? Data(contentsOf: url), data, "\(name) differs from AgentSchemaJSON: GRANITE_UPDATE_GOLDEN=1 rewrites it")
            XCTAssertNotNil(try JSONSerialization.jsonObject(with: data), name)
        }
    }

    func testTheStandardNamesWhatTheCodeHas() throws {
        let standard = try String(contentsOf: Self.folder.appendingPathComponent("GraniteAgent.md"), encoding: .utf8)
        XCTAssertTrue(standard.contains(AgentWire.version))
        for kind in AgentWire.kinds { XCTAssertTrue(standard.contains("`\(kind)`"), "the standard does not name the message `\(kind)`") }
        for field in AgentWire.Entry.fieldNames { XCTAssertTrue(standard.contains("`\(field)`"), "the standard does not name the entry field `\(field)`") }
        let record = AgentInstallation(name: "n", source: .git(url: "u", revision: "r"), revision: "r", granite: "g", sha256: "s", size: 1,
                                       modified: 1, builtAt: "b", entries: [])
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]).keys
        for key in keys { XCTAssertTrue(standard.contains("\"\(key)\""), "the standard's installation example lacks `\(key)`") }
        for name in AgentSchemaJSON.files.keys { XCTAssertTrue(standard.contains(name), "the standard does not point to \(name)") }
    }

    func testTheExamplesInTheStandardReadAsTheCodeWritesThem() throws {
        let schema = #"{"object": [{"name": "path", "required": true, "schema": "string"}, {"name": "filter", "required": false, "schema": {"choice": ["sepia"]}}, {"name": "sizes", "required": false, "schema": {"array": "integer"}}, {"name": "extra", "required": false, "schema": "any"}]}"#
        XCTAssertEqual(try JSONDecoder().decode(GraniteSchema.self, from: Data(schema.utf8)),
                       .object([.init(name: "path", schema: .string, required: true), .init(name: "filter", schema: .choice(["sepia"]), required: false),
                                .init(name: "sizes", schema: .array(.integer), required: false), .init(name: "extra", schema: .any, required: false)]))
        XCTAssertEqual(try AgentWire.read(Data(#"{"hello":{"pid":4512,"wire":"granite-agent/1"}}"#.utf8)), .hello(.init(pid: 4512)))
        XCTAssertEqual(try AgentWire.read(Data(#"{"answer":{"id":1,"object":{"n":3}}}"#.utf8)), .answer(.init(id: 1, object: .object(["n": .integer(3)]))))
        XCTAssertEqual(try AgentWire.read(Data(#"{"cancel":{}}"#.utf8)), .cancel)
    }
}
