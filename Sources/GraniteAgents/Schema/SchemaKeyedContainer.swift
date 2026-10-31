import Foundation

/// The keyed container a `SchemaDecoder` hands out: every field read is recorded, required when read with
/// `decode`, optional when read with `decodeIfPresent`, which answers nil.
struct SchemaKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let decoder: SchemaDecoder
    let codingPath: [CodingKey]

    var allKeys: [Key] { [] }
    func contains(_ key: Key) -> Bool { true }
    func decodeNil(forKey key: Key) throws -> Bool { false }

    private func read<T: Decodable>(_ type: T.Type, _ key: Key, required: Bool) throws -> T? {
        let (value, source) = decoder.probe(type, at: key)
        decoder.add(.init(name: key.stringValue, required: required, source: source))
        guard required else { return nil }
        guard let value else {
            throw DecodingError.valueNotFound(type, .init(codingPath: codingPath + [key], debugDescription: "recorded, not made"))
        }
        return value
    }

    private func required<T: Decodable>(_ type: T.Type, _ key: Key) throws -> T {
        // `read` throws rather than answer nil when the field is required.
        try read(type, key, required: true)!
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T { try required(type, key) }
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try required(type, key) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try required(type, key) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try required(type, key) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try required(type, key) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try required(type, key) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try required(type, key) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try required(type, key) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try required(type, key) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try required(type, key) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try required(type, key) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try required(type, key) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try required(type, key) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try required(type, key) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try required(type, key) }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? { try read(type, key, required: false) }
    func decodeIfPresent(_ type: Bool.Type, forKey key: Key) throws -> Bool? { try read(type, key, required: false) }
    func decodeIfPresent(_ type: String.Type, forKey key: Key) throws -> String? { try read(type, key, required: false) }
    func decodeIfPresent(_ type: Double.Type, forKey key: Key) throws -> Double? { try read(type, key, required: false) }
    func decodeIfPresent(_ type: Float.Type, forKey key: Key) throws -> Float? { try read(type, key, required: false) }
    func decodeIfPresent(_ type: Int.Type, forKey key: Key) throws -> Int? { try read(type, key, required: false) }
    func decodeIfPresent(_ type: Int8.Type, forKey key: Key) throws -> Int8? { try read(type, key, required: false) }
    func decodeIfPresent(_ type: Int16.Type, forKey key: Key) throws -> Int16? { try read(type, key, required: false) }
    func decodeIfPresent(_ type: Int32.Type, forKey key: Key) throws -> Int32? { try read(type, key, required: false) }
    func decodeIfPresent(_ type: Int64.Type, forKey key: Key) throws -> Int64? { try read(type, key, required: false) }
    func decodeIfPresent(_ type: UInt.Type, forKey key: Key) throws -> UInt? { try read(type, key, required: false) }
    func decodeIfPresent(_ type: UInt8.Type, forKey key: Key) throws -> UInt8? { try read(type, key, required: false) }
    func decodeIfPresent(_ type: UInt16.Type, forKey key: Key) throws -> UInt16? { try read(type, key, required: false) }
    func decodeIfPresent(_ type: UInt32.Type, forKey key: Key) throws -> UInt32? { try read(type, key, required: false) }
    func decodeIfPresent(_ type: UInt64.Type, forKey key: Key) throws -> UInt64? { try read(type, key, required: false) }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        let recorder = decoder.child(at: key)
        decoder.add(.init(name: key.stringValue, required: true, source: .nested(recorder)))
        return try recorder.container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        let recorder = decoder.child(at: key)
        decoder.add(.init(name: key.stringValue, required: true, source: .nested(recorder)))
        return try recorder.unkeyedContainer()
    }

    /// A superclass's fields are this object's.
    func superDecoder() throws -> Decoder { decoder }

    func superDecoder(forKey key: Key) throws -> Decoder {
        let recorder = decoder.child(at: key)
        decoder.add(.init(name: key.stringValue, required: true, source: .nested(recorder)))
        return recorder
    }
}
