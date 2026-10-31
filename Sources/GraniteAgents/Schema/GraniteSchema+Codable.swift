//  WHAT: A schema as data: how an agent's input schema crosses a process or a machine, and how an installation
//        keeps it, tagged so it reads back exactly. `"string"`, `"integer"`, `"number"`, `"boolean"`, `"any"`;
//        `{"choice": [...]}`, `{"array": <schema>}`, `{"object": [{"name", "schema", "required"}]}`.
//  PIN:  NOT JSON SCHEMA. JSON Schema is what a host shows a model (`jsonSchema(notes:hiding:)`); it keeps
//        properties in a dictionary and says nothing for `.any`, so it cannot be read back. This form keeps an
//        object's fields in the order its decoding read them, and `.any` as itself.

import Foundation

extension GraniteSchema: Codable {
    private enum Tag: String, CodingKey { case choice, array, object }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let word = try? single.decode(String.self) {
            switch word {
            case "string": self = .string
            case "integer": self = .integer
            case "number": self = .number
            case "boolean": self = .boolean
            case "any": self = .any
            default:
                throw DecodingError.dataCorruptedError(in: single, debugDescription: "no schema is called \"\(word)\"")
            }
            return
        }
        let tagged = try decoder.container(keyedBy: Tag.self)
        if let values = try tagged.decodeIfPresent([String].self, forKey: .choice) {
            self = .choice(values)
        } else if let element = try tagged.decodeIfPresent(GraniteSchema.self, forKey: .array) {
            self = .array(element)
        } else if let fields = try tagged.decodeIfPresent([Field].self, forKey: .object) {
            self = .object(fields)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "a schema is a word or one of choice, array, object"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .string: var single = encoder.singleValueContainer(); try single.encode("string")
        case .integer: var single = encoder.singleValueContainer(); try single.encode("integer")
        case .number: var single = encoder.singleValueContainer(); try single.encode("number")
        case .boolean: var single = encoder.singleValueContainer(); try single.encode("boolean")
        case .any: var single = encoder.singleValueContainer(); try single.encode("any")
        case .choice(let values): var tagged = encoder.container(keyedBy: Tag.self); try tagged.encode(values, forKey: .choice)
        case .array(let element): var tagged = encoder.container(keyedBy: Tag.self); try tagged.encode(element, forKey: .array)
        case .object(let fields): var tagged = encoder.container(keyedBy: Tag.self); try tagged.encode(fields, forKey: .object)
        }
    }
}

extension GraniteSchema.Field: Codable {
    private enum Key: String, CodingKey { case name, schema, required }

    public init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: Key.self)
        self.init(name: try keyed.decode(String.self, forKey: .name), schema: try keyed.decode(GraniteSchema.self, forKey: .schema),
                  required: try keyed.decode(Bool.self, forKey: .required))
    }

    public func encode(to encoder: Encoder) throws {
        var keyed = encoder.container(keyedBy: Key.self)
        try keyed.encode(name, forKey: .name)
        try keyed.encode(schema, forKey: .schema)
        try keyed.encode(required, forKey: .required)
    }
}
