import Foundation

/// A `Decoder` that reads nothing and records what a type's `init(from:)` asks for: the fields it reads, by
/// name and kind, and which it reads with `decodeIfPresent`. `GraniteSchema.of` is made from one.
final class SchemaDecoder: Decoder {
    /// Past this many levels a value is recorded as `.any`: a type that holds itself stops here.
    static let maxDepth = 8

    /// One field a keyed container read, or the element an unkeyed one read.
    struct Read {
        let name: String
        let required: Bool
        let source: Source
    }

    /// Where a read's schema comes from: known at once, or a child recorder that is filled as the decoding
    /// goes on.
    enum Source {
        case schema(GraniteSchema)
        case nested(SchemaDecoder)

        var schema: GraniteSchema {
            switch self {
            case .schema(let schema): return schema
            case .nested(let decoder): return decoder.schema
            }
        }
    }

    private enum Shape { case unread, keyed, unkeyed, single }

    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any] = [:]
    private let depth: Int
    private var shape = Shape.unread
    private var reads: [Read] = []
    private var single: Source = .schema(.any)

    init(codingPath: [CodingKey] = [], depth: Int = 0) {
        self.codingPath = codingPath
        self.depth = depth
    }

    /// What the decoding asked for, as far as it went.
    var schema: GraniteSchema {
        switch shape {
        case .unread: return .any
        case .keyed:
            var seen: Set<String> = []
            return .object(reads.filter { seen.insert($0.name).inserted }
                .map { GraniteSchema.Field(name: $0.name, schema: $0.source.schema, required: $0.required) })
        case .unkeyed: return .array(reads.first?.source.schema ?? .any)
        case .single: return single.schema
        }
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        shape = .keyed
        return KeyedDecodingContainer(SchemaKeyedContainer<Key>(decoder: self, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        shape = .unkeyed
        return SchemaUnkeyedContainer(decoder: self, codingPath: codingPath)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        shape = .single
        return SchemaSingleValueContainer(decoder: self, codingPath: codingPath)
    }

    func add(_ read: Read) { reads.append(read) }

    func setSingle(_ source: Source) { single = source }

    /// A recorder for what is read under `key`, one level down.
    func child(at key: CodingKey?) -> SchemaDecoder {
        SchemaDecoder(codingPath: codingPath + (key.map { [$0] } ?? []), depth: depth + 1)
    }

    /// A value of `T` made from nothing, and where its schema comes from: a primitive's zero, an enum's
    /// first case, or what `T`'s own decoding made of a child recorder. The value is nil when `T` cannot be
    /// made from nothing; its schema is still what was read.
    func probe<T: Decodable>(_ type: T.Type, at key: CodingKey?) -> (value: T?, source: Source) {
        if let (value, schema) = Self.primitive(type) { return (value as? T, .schema(schema)) }
        if let (first, values) = Self.choice(type) { return (first as? T, .schema(.choice(values))) }
        guard depth < Self.maxDepth else { return (nil, .schema(.any)) }
        let recorder = child(at: key)
        return (try? T(from: recorder), .nested(recorder))
    }

    private static func primitive<T>(_ type: T.Type) -> (Any, GraniteSchema)? {
        switch type {
        case is String.Type: return ("", .string)
        case is Bool.Type: return (false, .boolean)
        case is Int.Type: return (0 as Int, .integer)
        case is Int8.Type: return (0 as Int8, .integer)
        case is Int16.Type: return (0 as Int16, .integer)
        case is Int32.Type: return (0 as Int32, .integer)
        case is Int64.Type: return (0 as Int64, .integer)
        case is UInt.Type: return (0 as UInt, .integer)
        case is UInt8.Type: return (0 as UInt8, .integer)
        case is UInt16.Type: return (0 as UInt16, .integer)
        case is UInt32.Type: return (0 as UInt32, .integer)
        case is UInt64.Type: return (0 as UInt64, .integer)
        case is Double.Type: return (0 as Double, .number)
        case is Float.Type: return (0 as Float, .number)
        case is URL.Type: return (URL(fileURLWithPath: "/"), .string)
        case is UUID.Type: return (UUID(), .string)
        default: return nil
        }
    }

    /// The cases of an enum of `String` raw values that lists them, and the first, to stand for a value.
    private static func choice<T>(_ type: T.Type) -> (Any, [String])? {
        guard let iterable = type as? any CaseIterable.Type else { return nil }
        let cases = allCases(of: iterable)
        let values = cases.compactMap { ($0 as? any RawRepresentable)?.rawValue as? String }
        guard let first = cases.first, values.count == cases.count else { return nil }
        return (first, values)
    }

    private static func allCases<C: CaseIterable>(of type: C.Type) -> [Any] {
        Array(type.allCases)
    }
}
