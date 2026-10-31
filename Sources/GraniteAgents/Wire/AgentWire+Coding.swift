import Foundation

extension AgentWire: Codable {
    private enum Key: String, CodingKey { case hello, perform, note, model, answer, output, failed, cancel, entries }
    private struct Empty: Codable {}

    public init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: Key.self)
        if let value = try keyed.decodeIfPresent(Hello.self, forKey: .hello) { self = .hello(value) }
        else if let value = try keyed.decodeIfPresent(Perform.self, forKey: .perform) { self = .perform(value) }
        else if let value = try keyed.decodeIfPresent(String.self, forKey: .note) { self = .note(value) }
        else if let value = try keyed.decodeIfPresent(ModelAsk.self, forKey: .model) { self = .model(value) }
        else if let value = try keyed.decodeIfPresent(ModelAnswer.self, forKey: .answer) { self = .answer(value) }
        else if keyed.contains(.output) { self = .output(try keyed.decode(AgentJSON.self, forKey: .output)) }
        else if let value = try keyed.decodeIfPresent(String.self, forKey: .failed) { self = .failed(value) }
        else if keyed.contains(.cancel) { self = .cancel }
        else if let value = try keyed.decodeIfPresent([Entry].self, forKey: .entries) { self = .entries(value) }
        else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "a message is one of \(AgentWire.kinds.joined(separator: ", "))"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var keyed = encoder.container(keyedBy: Key.self)
        switch self {
        case .hello(let value): try keyed.encode(value, forKey: .hello)
        case .perform(let value): try keyed.encode(value, forKey: .perform)
        case .note(let value): try keyed.encode(value, forKey: .note)
        case .model(let value): try keyed.encode(value, forKey: .model)
        case .answer(let value): try keyed.encode(value, forKey: .answer)
        case .output(let value): try keyed.encode(value, forKey: .output)
        case .failed(let value): try keyed.encode(value, forKey: .failed)
        case .cancel: try keyed.encode(Empty(), forKey: .cancel)
        case .entries(let value): try keyed.encode(value, forKey: .entries)
        }
    }

    /// The message as one line of JSON, newline included.
    public func line() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }

    /// The message one line holds.
    public static func read(_ line: Data) throws -> AgentWire {
        try JSONDecoder().decode(AgentWire.self, from: line)
    }
}
