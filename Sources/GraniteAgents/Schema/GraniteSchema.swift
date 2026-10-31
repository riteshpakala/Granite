//  WHAT: What a `Decodable` type takes, read off its own decoding: each field's name and kind, whether it
//        must be there, and for a field with a fixed set of values, the values. What an app shows a model
//        as a package agent's parameters, as JSON Schema.
//  PIN:  READ, NOT WRITTEN. The schema is recorded by decoding the type once from nothing
//        (`SchemaDecoder`): a field read with `decode` is required, one read with `decodeIfPresent` is not,
//        so an `Optional` field is optional and a field with a default value in a synthesized `init(from:)`
//        is still required. An enum of `String` raw values that lists its cases is a choice of those
//        values. A field whose type cannot be made from nothing still has its kind recorded, but a
//        required one ends the walk: what comes after it in `init(from:)` is not read.

import Foundation

public indirect enum GraniteSchema: Sendable, Equatable {
    case string
    case integer
    case number
    case boolean
    /// One of these strings: an enum with `String` raw values that lists its cases.
    case choice([String])
    case array(GraniteSchema)
    case object([Field])
    /// A value whose decoding said nothing the recorder could read.
    case any

    public struct Field: Sendable, Equatable {
        public let name: String
        public let schema: GraniteSchema
        public let required: Bool

        public init(name: String, schema: GraniteSchema, required: Bool) {
            self.name = name; self.schema = schema; self.required = required
        }
    }

    /// The schema of `type`, recorded by decoding it once from nothing.
    public static func of<T: Decodable>(_ type: T.Type) -> GraniteSchema {
        SchemaDecoder().probe(type, at: nil).source.schema
    }

    /// An object's fields, in the order its decoding read them; none for anything else.
    public var fields: [Field] {
        if case .object(let fields) = self { return fields }
        return []
    }

    /// As JSON Schema, with `notes` said beside the fields they name and the fields in `hiding` left out.
    public func jsonSchema(notes: [String: String] = [:], hiding: Set<String> = []) -> Data {
        (try? JSONSerialization.data(withJSONObject: jsonObject(notes: notes, hiding: hiding), options: [.sortedKeys]))
            ?? Data("{}".utf8)
    }

    func jsonObject(notes: [String: String] = [:], hiding: Set<String> = []) -> [String: Any] {
        switch self {
        case .string: return ["type": "string"]
        case .integer: return ["type": "integer"]
        case .number: return ["type": "number"]
        case .boolean: return ["type": "boolean"]
        case .choice(let values): return ["type": "string", "enum": values]
        case .array(let element): return ["type": "array", "items": element.jsonObject()]
        case .object(let fields):
            let shown = fields.filter { !hiding.contains($0.name) }
            var properties: [String: Any] = [:]
            for field in shown {
                var property = field.schema.jsonObject()
                if let note = notes[field.name] { property["description"] = note }
                properties[field.name] = property
            }
            return ["type": "object", "properties": properties, "required": shown.filter(\.required).map(\.name)]
        case .any: return [:]
        }
    }
}
