import Foundation

/// The single-value container a `SchemaDecoder` hands out: the value's type is the schema.
struct SchemaSingleValueContainer: SingleValueDecodingContainer {
    let decoder: SchemaDecoder
    let codingPath: [CodingKey]

    func decodeNil() -> Bool { false }

    private func value<T: Decodable>(_ type: T.Type) throws -> T {
        let (value, source) = decoder.probe(type, at: nil)
        decoder.setSingle(source)
        guard let value else {
            throw DecodingError.valueNotFound(type, .init(codingPath: codingPath, debugDescription: "recorded, not made"))
        }
        return value
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T { try value(type) }
    func decode(_ type: Bool.Type) throws -> Bool { try value(type) }
    func decode(_ type: String.Type) throws -> String { try value(type) }
    func decode(_ type: Double.Type) throws -> Double { try value(type) }
    func decode(_ type: Float.Type) throws -> Float { try value(type) }
    func decode(_ type: Int.Type) throws -> Int { try value(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { try value(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { try value(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { try value(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { try value(type) }
    func decode(_ type: UInt.Type) throws -> UInt { try value(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try value(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try value(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try value(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try value(type) }
}
