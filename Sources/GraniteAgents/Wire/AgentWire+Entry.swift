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
        public var makes: [AgentMake]?
        /// What it reads of the person's files, as UTType identifiers; left out when it reads none.
        public var takes: [String]?
        /// What it keeps between calls, in its own sentence; left out when it keeps nothing.
        public var keeps: String?
        /// The agents it calls, each by its word; left out when it needs none.
        public var needs: [AgentNeed]?
        // A worker spec's.
        public var toolNames: [String]?
        public var budget: WorkerBudget?
        public var shell: Bool?
        public var reportRule: String?

        public init(kind: Kind, word: String, summary: String, module: String, type: String, schema: GraniteSchema? = nil,
                    fields: [String: String]? = nil, lanes: Int? = nil, guide: String? = nil, makes: [AgentMake]? = nil,
                    takes: [String]? = nil, keeps: String? = nil, needs: [AgentNeed]? = nil,
                    toolNames: [String]? = nil, budget: WorkerBudget? = nil, shell: Bool? = nil, reportRule: String? = nil) {
            self.kind = kind; self.word = word; self.summary = summary; self.module = module; self.type = type
            self.schema = schema; self.fields = fields; self.lanes = lanes; self.guide = guide; self.makes = makes
            self.takes = takes; self.keeps = keeps; self.needs = needs
            self.toolNames = toolNames; self.budget = budget; self.shell = shell; self.reportRule = reportRule
        }

        /// What a roster entry says of itself.
        public init(_ entry: GraniteRosterEntry) {
            switch entry {
            case .package(let package):
                self.init(kind: .package, word: package.word, summary: package.summary, module: package.module, type: package.type,
                          schema: package.schema, fields: package.fields, lanes: package.lanes, guide: package.guide.isEmpty ? nil : package.guide,
                          makes: package.makes.isEmpty ? nil : package.makes, takes: package.takes.isEmpty ? nil : package.takes,
                          keeps: package.keeps, needs: package.needs.isEmpty ? nil : package.needs)
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
                                                fields: fields ?? [:], lanes: lanes, guide: guide ?? "", makes: makes ?? [],
                                                takes: takes ?? [], keeps: keeps, needs: needs ?? [], perform: perform))
            case .worker:
                return .worker(AnyWorkerSpec(word: word, summary: summary, module: module, type: type, toolNames: toolNames ?? [],
                                             budget: budget ?? .reading, shell: shell ?? false, reportRule: reportRule))
            }
        }

        /// Every field an entry may say, in the order the standard lists them.
        public static let fieldNames = ["kind", "word", "summary", "module", "type", "schema", "fields", "lanes", "guide", "makes",
                                        "takes", "keeps", "needs", "toolNames", "budget", "shell", "reportRule"]
    }
}
