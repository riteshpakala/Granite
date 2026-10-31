import Foundation

/// A package agent with its type erased, as a roster keeps it: what it is called and takes, and a call that
/// takes JSON and answers JSON. Made where the type is known, in the package's record, so an app that never
/// imports the package can still run it.
public struct AnyAgentPackage: Sendable {
    /// The `Input` field a host fills with the folder it works in, and does not show a model.
    public static let directoryField = "directory"

    public let word: String
    public let summary: String
    /// The module that declares it.
    public let module: String
    /// Its type, as `Module.Type`.
    public let type: String
    /// What its `Input` takes, read off its own decoding.
    public let schema: GraniteSchema
    /// The lines it says beside its fields.
    public let fields: [String: String]
    /// How many calls run at once; nil: no bound.
    public let lanes: Int?
    /// How to use it well, in its own words: what a host puts in its prompt when the agent is asked for.
    public let guide: String
    private let call: @Sendable (Data, AgentHost) async throws -> Data

    public init<P: GraniteAgentPackage>(_ package: P.Type) {
        word = P.word
        summary = P.summary
        type = String(reflecting: P.self)
        module = type.split(separator: ".").first.map(String.init) ?? type
        schema = GraniteSchema.of(P.Input.self)
        fields = P.fields
        lanes = P.lanes
        guide = P.guide
        call = { data, host in try await Self.perform(P.self, data, host: host) }
    }

    /// A package described rather than linked: what an entry says of it (`AgentWire.Entry`), and a call that runs
    /// wherever the package lives. `RemoteAgent` makes one whose call runs a process of its own.
    public init(word: String, summary: String, module: String, type: String, schema: GraniteSchema, fields: [String: String],
                lanes: Int?, guide: String, perform: @escaping @Sendable (Data, AgentHost) async throws -> Data) {
        self.word = word
        self.summary = summary
        self.module = module
        self.type = type
        self.schema = schema
        self.fields = fields
        self.lanes = lanes
        self.guide = guide
        call = perform
    }

    /// Whether the package takes the host's folder (`directoryField`).
    public var takesDirectory: Bool {
        guard case .object(let fields) = schema else { return false }
        return fields.contains { $0.name == Self.directoryField }
    }

    /// Runs one call: the input decoded, the run hosted on the package's own center and offered `host`, the
    /// output encoded. Cancelling the awaiting task cancels the run.
    public func perform(_ input: Data, host: AgentHost = .none) async throws -> Data {
        try await call(input, host)
    }

    private static func perform<P: GraniteAgentPackage>(_ package: P.Type, _ data: Data, host offered: AgentHost) async throws -> Data {
        let input: P.Input
        do {
            input = try JSONDecoder().decode(P.Input.self, from: data)
        } catch {
            throw AgentPackageError.input(word: P.word, reason: "\(error)")
        }
        let host = await MainActor.run { AgentPackageHost<P>.shared() }
        let id = "\(P.word)-\(UUID().uuidString.prefix(8).lowercased())"
        // The tap before the run, so no event is missed; it ends with the run.
        let tap = host.executable.events(key: id)
        let heard = Task { () -> [P.Event] in
            var events: [P.Event] = []
            for await event in tap { events.append(event) }
            return events
        }
        do {
            _ = try await host.executable.perform(AgentPackageCall(id: id, input: input, host: offered))
        } catch {
            heard.cancel()
            throw error
        }
        guard let output = P.output(from: await heard.value) else { throw AgentPackageError.noOutput(word: P.word) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(output)
    }
}
