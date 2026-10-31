import Foundation

/// The model a host has loaded, as a package may ask it: a JSON object that fits a schema, or text. Said
/// without the host's types, so any app can offer its own: a schema is JSON Schema, an answer is JSON or text.
///
/// PIN: throwing, never nil. A package that asks the model depends on the answer, so a failed ask fails the
/// run with a sentence (`AgentHostError`); a host whose own generator answers nil says so as `.noAnswer`.
public protocol AgentHostModel: Sendable {
    /// A JSON object that fits `schema` (JSON Schema). Throws `AgentHostError.noAnswer` when nothing the model
    /// said parsed, or `seconds` passed.
    func object(schema: Data, system: String, user: String, maxTokens: Int, seconds: Double) async throws -> Data
    /// Text, whole.
    func text(system: String, user: String, maxTokens: Int, seconds: Double) async throws -> String
}

extension AgentHostModel {
    /// A JSON object that fits `schema`, said beside its fields with `notes`.
    public func object(schema: GraniteSchema, notes: [String: String] = [:], system: String, user: String,
                       maxTokens: Int, seconds: Double) async throws -> Data {
        try await object(schema: schema.jsonSchema(notes: notes), system: system, user: user, maxTokens: maxTokens, seconds: seconds)
    }

    /// A `T`, its schema read off its own decoding (`GraniteSchema.of`); `AgentHostError.answer` when the
    /// model's JSON does not decode as one.
    public func object<T: Decodable>(_ type: T.Type, notes: [String: String] = [:], system: String, user: String,
                                     maxTokens: Int, seconds: Double) async throws -> T {
        let data = try await object(schema: GraniteSchema.of(type), notes: notes, system: system, user: user,
                                    maxTokens: maxTokens, seconds: seconds)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AgentHostError.answer("\(error)")
        }
    }
}
