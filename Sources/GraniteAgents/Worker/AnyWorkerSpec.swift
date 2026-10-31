import Foundation

/// A worker spec with its type erased, as a roster keeps it.
public struct AnyWorkerSpec: Sendable {
    public let word: String
    public let summary: String
    /// The module that declares it.
    public let module: String
    /// Its type, as `Module.Type`.
    public let type: String
    public let toolNames: [String]
    public let budget: WorkerBudget
    public let shell: Bool
    public let reportRule: String?
    private let open: @Sendable (_ word: String, _ project: String) -> String?

    public init<W: GraniteWorkerSpec>(_ spec: W.Type) {
        word = W.word
        summary = W.summary
        type = String(reflecting: W.self)
        module = type.split(separator: ".").first.map(String.init) ?? type
        toolNames = W.toolNames
        budget = W.budget
        shell = W.shell
        reportRule = W.reportRule
        open = { word, project in W.opening(word: word, project: project) }
    }

    /// A worker spec described rather than linked (`AgentWire.Entry`): everything but its opening, which is the
    /// host's own.
    public init(word: String, summary: String, module: String, type: String, toolNames: [String], budget: WorkerBudget,
                shell: Bool, reportRule: String?) {
        self.word = word
        self.summary = summary
        self.module = module
        self.type = type
        self.toolNames = toolNames
        self.budget = budget
        self.shell = shell
        self.reportRule = reportRule
        open = { _, _ in nil }
    }

    /// Who it is, opening its prompt; nil keeps the app's own opening.
    public func opening(word: String, project: String) -> String? {
        open(word, project)
    }
}
