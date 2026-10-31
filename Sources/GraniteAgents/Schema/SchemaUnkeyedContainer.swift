import Foundation

/// The unkeyed container a `SchemaDecoder` hands out: one element long, so an array's decoding reads its
/// element's type once and the recorder keeps that as the array's items.
struct SchemaUnkeyedContainer: UnkeyedDecodingContainer {
    struct Index: CodingKey {
        let intValue: Int?
        var stringValue: String { "\(intValue ?? 0)" }
        init(_ index: Int) { intValue = index }
        init?(stringValue: String) { return nil }
        init?(intValue: Int) { self.intValue = intValue }
    }

    let decoder: SchemaDecoder
    let codingPath: [CodingKey]
    private(set) var currentIndex = 0

    init(decoder: SchemaDecoder, codingPath: [CodingKey]) {
        self.decoder = decoder; self.codingPath = codingPath
    }

    var count: Int? { 1 }
    var isAtEnd: Bool { currentIndex >= 1 }

    mutating func decodeNil() throws -> Bool { false }

    private mutating func element<T: Decodable>(_ type: T.Type) throws -> T {
        let key = Index(currentIndex)
        let (value, source) = decoder.probe(type, at: key)
        if currentIndex == 0 { decoder.add(.init(name: "", required: true, source: source)) }
        currentIndex += 1
        guard let value else {
            throw DecodingError.valueNotFound(type, .init(codingPath: codingPath + [key], debugDescription: "recorded, not made"))
        }
        return value
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T { try element(type) }
    mutating func decode(_ type: Bool.Type) throws -> Bool { try element(type) }
    mutating func decode(_ type: String.Type) throws -> String { try element(type) }
    mutating func decode(_ type: Double.Type) throws -> Double { try element(type) }
    mutating func decode(_ type: Float.Type) throws -> Float { try element(type) }
    mutating func decode(_ type: Int.Type) throws -> Int { try element(type) }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { try element(type) }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { try element(type) }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { try element(type) }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { try element(type) }
    mutating func decode(_ type: UInt.Type) throws -> UInt { try element(type) }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try element(type) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try element(type) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try element(type) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try element(type) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        let recorder = decoder.child(at: Index(currentIndex))
        if currentIndex == 0 { decoder.add(.init(name: "", required: true, source: .nested(recorder))) }
        currentIndex += 1
        return try recorder.container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let recorder = decoder.child(at: Index(currentIndex))
        if currentIndex == 0 { decoder.add(.init(name: "", required: true, source: .nested(recorder))) }
        currentIndex += 1
        return try recorder.unkeyedContainer()
    }

    mutating func superDecoder() throws -> Decoder {
        let recorder = decoder.child(at: Index(currentIndex))
        if currentIndex == 0 { decoder.add(.init(name: "", required: true, source: .nested(recorder))) }
        currentIndex += 1
        return recorder
    }
}
