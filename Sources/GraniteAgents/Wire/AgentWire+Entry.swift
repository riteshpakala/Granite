import Foundation

extension AgentWire {
    /// One agent, described: everything a host needs to offer it and call it without the type that declares it.
    /// What `--describe` prints and what an installation keeps.
    public struct Entry: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable { case package, worker }

        public var kind: Kind
        public var word: String
        public var summary: String
        public var module: String
        public var type: String
        // A package agent's.
        public var schema: GraniteSchema?
        public var fields: [String: String]?
        public var lanes: Int?
        public var guide: String?
        // A worker spec's.
        public var toolNames: [String]?
        public var budget: WorkerBudget?
        public var shell: Bool?
        public var reportRule: String?

        public init(kind: Kind, word: String, summary: String, module: String, type: String, schema: GraniteSchema? = nil,
                    fields: [String: String]? = nil, lanes: Int? = nil, guide: String? = nil, toolNames: [String]? = nil,
                    budget: WorkerBudget? = nil, shell: Bool? = nil, reportRule: String? = nil) {
            self.kind = kind; self.word = word; self.summary = summary; self.module = module; self.type = type
            self.schema = schema; self.fields = fields; self.lanes = lanes; self.guide = guide
            self.toolNames = toolNames; self.budget = budget; self.shell = shell; self.reportRule = reportRule
        }

        /// What a roster entry says of itself.
        public init(_ entry: GraniteRosterEntry) {
            switch entry {
            case .package(let package):
                self.init(kind: .package, word: package.word, summary: package.summary, module: package.module, type: package.type,
                          schema: package.schema, fields: package.fields, lanes: package.lanes, guide: package.guide.isEmpty ? nil : package.guide)
            case .worker(let worker):
                self.init(kind: .worker, word: worker.word, summary: worker.summary, module: worker.module, type: worker.type,
                          toolNames: worker.toolNames, budget: worker.budget, shell: worker.shell, reportRule: worker.reportRule)
            }
        }

        /// The entry a roster keeps, its package's calls made by `perform`.
        public func rosterEntry(perform: @escaping @Sendable (Data, AgentHost) async throws -> Data) -> GraniteRosterEntry {
            switch kind {
            case .package:
                return .package(AnyAgentPackage(word: word, summary: summary, module: module, type: type, schema: schema ?? .object([]),
                                                fields: fields ?? [:], lanes: lanes, guide: guide ?? "", perform: perform))
            case .worker:
                return .worker(AnyWorkerSpec(word: word, summary: summary, module: module, type: type, toolNames: toolNames ?? [],
                                             budget: budget ?? .reading, shell: shell ?? false, reportRule: reportRule))
            }
        }

        /// Every field an entry may say, in the order the standard lists them.
        public static let fieldNames = ["kind", "word", "summary", "module", "type", "schema", "fields", "lanes", "guide",
                                        "toolNames", "budget", "shell", "reportRule"]
    }
}
