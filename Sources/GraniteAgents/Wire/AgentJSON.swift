import Foundation

/// A JSON value carried whole inside a wire message: a call's input, its output, a schema, a model's answer.
/// Integers stay integers; an object's keys are written sorted.
public indirect enum AgentJSON: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([AgentJSON])
    case object([String: AgentJSON])

    /// The value `data` holds; `nil` when it is not JSON.
    public init?(data: Data) {
        guard let value = try? JSONDecoder().decode(AgentJSON.self, from: data) else { return nil }
        self = value
    }

    /// As JSON, keys sorted.
    public func data() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data("null".utf8)
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null }
        else if let value = try? single.decode(Bool.self) { self = .bool(value) }
        else if let value = try? single.decode(Int.self) { self = .integer(value) }
        else if let value = try? single.decode(Double.self) { self = .number(value) }
        else if let value = try? single.decode(String.self) { self = .string(value) }
        else if let value = try? single.decode([AgentJSON].self) { self = .array(value) }
        else { self = .object(try single.decode([String: AgentJSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .null: try single.encodeNil()
        case .bool(let value): try single.encode(value)
        case .integer(let value): try single.encode(value)
        case .number(let value): try single.encode(value)
        case .string(let value): try single.encode(value)
        case .array(let value): try single.encode(value)
        case .object(let value): try single.encode(value)
        }
    }
}
