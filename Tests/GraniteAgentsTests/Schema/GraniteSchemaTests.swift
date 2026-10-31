import Foundation
import XCTest
@testable import GraniteAgents

/// A type's schema is read off its own decoding: what it reads with `decode` is required, what it reads
/// with `decodeIfPresent` is not, an enum that lists its `String` cases is a choice, and the walk stops
/// where a required field cannot be made.
final class GraniteSchemaTests: XCTestCase {
    struct Flat: Decodable { var name: String; var count: Int; var ratio: Double; var on: Bool; var note: String? }

    enum Tone: String, Codable, CaseIterable { case warm, cool }

    struct Nested: Decodable {
        struct Inner: Decodable { var depth: Int? }
        var tone: Tone
        var tones: [Tone]?
        var inner: Inner
    }

    /// Validates its path before it reads what comes after it.
    struct Checked: Decodable {
        enum CodingKeys: CodingKey { case path, after }
        var path: String
        var after: Int
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decode(String.self, forKey: .path)
            guard !path.isEmpty else { throw DecodingError.dataCorruptedError(forKey: .path, in: container, debugDescription: "empty") }
            after = try container.decode(Int.self, forKey: .after)
        }
    }

    private func field(_ name: String, _ schema: GraniteSchema, _ required: Bool) -> GraniteSchema.Field {
        GraniteSchema.Field(name: name, schema: schema, required: required)
    }

    func testAFlatTypeIsItsFieldsInOrder() {
        XCTAssertEqual(GraniteSchema.of(Flat.self), .object([
            field("name", .string, true), field("count", .integer, true), field("ratio", .number, true),
            field("on", .boolean, true), field("note", .string, false),
        ]))
    }

    func testChoicesArraysAndNestedObjects() {
        XCTAssertEqual(GraniteSchema.of(Nested.self), .object([
            field("tone", .choice(["warm", "cool"]), true),
            field("tones", .array(.choice(["warm", "cool"])), false),
            field("inner", .object([field("depth", .integer, false)]), true),
        ]))
        XCTAssertEqual(GraniteSchema.of([String].self), .array(.string))
    }

    func testTheWalkStopsWhereARequiredFieldCannotBeMade() {
        XCTAssertEqual(GraniteSchema.of(Checked.self), .object([field("path", .string, true)]),
                       "the empty path failed its own check, so `after` was never read")
    }

    func testJSONSchemaSaysNotesAndHidesWhatTheHostFills() throws {
        let data = GraniteSchema.of(EchoPackage.Input.self).jsonSchema(notes: EchoPackage.fields, hiding: ["directory"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try XCTUnwrap(json["properties"] as? [String: [String: Any]])
        XCTAssertEqual(Set(properties.keys), ["text", "times", "delay"])
        XCTAssertEqual(properties["text"]?["type"] as? String, "string")
        XCTAssertEqual(properties["text"]?["description"] as? String, "what to say")
        XCTAssertEqual(properties["delay"]?["type"] as? String, "number")
        XCTAssertEqual(json["required"] as? [String], ["text"])
    }
}
