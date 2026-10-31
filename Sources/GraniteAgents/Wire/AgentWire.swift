//  WHAT: One message between a host and an agent running somewhere else: a line of JSON, one key naming the
//        message. The conversation of `granite-agent/1`, which `Schema/GraniteAgent.md` sets out.
//
//            agent → host   {"hello": {"wire": "granite-agent/1", "pid": 4512}}
//            host → agent   {"perform": {"word": "plate", "input": {...}, "directory": "/p", "ask": "...", "model": true}}
//            agent → host   {"note": "round 1: measured clean"}
//            agent → host   {"model": {"id": 1, "object": {"schema": {...}, "system": "...", "user": "...", ...}}}
//            host → agent   {"answer": {"id": 1, "object": {...}}}
//            agent → host   {"output": {...}}   or   {"failed": "a sentence"}
//            host → agent   {"cancel": {}}
//            agent → host   {"entries": [...]}   (only with --describe)
//
//  PIN:  ONE CALL, THEN GONE. A process answers one `perform` with exactly one `output` or `failed` and exits;
//        whatever it made to answer (a GPU device, a web page, a model's asks) goes with it.
//  PIN:  THE HOST'S END CLOSING IS NOT A CANCEL. It means the host sends nothing more: the call runs on and an
//        ask of the model is told there is no answer. `cancel`, or SIGTERM, cancels.
//  PIN:  READ WHAT YOU KNOW. A field a reader does not know is ignored; a message it does not know ends the
//        call as a protocol failure. A new optional field is a minor change; anything else is a new major.

import Foundation

public enum AgentWire: Sendable, Equatable {
    /// The version every first line names, and the one major this build speaks.
    public static let version = "granite-agent/1"
    public static let major = 1

    case hello(Hello)
    case perform(Perform)
    case note(String)
    case model(ModelAsk)
    case answer(ModelAnswer)
    case output(AgentJSON)
    case failed(String)
    case cancel
    case entries([Entry])

    /// The agent's first line: what it speaks, and which process it is.
    public struct Hello: Codable, Sendable, Equatable {
        public var wire: String
        public var pid: Int32?
        public init(wire: String = AgentWire.version, pid: Int32? = nil) { self.wire = wire; self.pid = pid }
    }

    /// The one call a process answers.
    public struct Perform: Codable, Sendable, Equatable {
        public var word: String
        public var input: AgentJSON
        public var directory: String?
        public var ask: String?
        /// Whether the host offers its model; an agent that asks without one is told so.
        public var model: Bool
        public init(word: String, input: AgentJSON, directory: String? = nil, ask: String? = nil, model: Bool = false) {
            self.word = word; self.input = input; self.directory = directory; self.ask = ask; self.model = model
        }
    }

    /// What an agent asks the host's model, by an id its answer comes back under.
    public struct ModelAsk: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable { case object, text }
        public var id: Int
        public var kind: Kind
        /// JSON Schema, for an object.
        public var schema: AgentJSON?
        public var system: String
        public var user: String
        public var maxTokens: Int
        public var seconds: Double
        public init(id: Int, kind: Kind, schema: AgentJSON? = nil, system: String, user: String, maxTokens: Int, seconds: Double) {
            self.id = id; self.kind = kind; self.schema = schema; self.system = system; self.user = user
            self.maxTokens = maxTokens; self.seconds = seconds
        }
    }

    /// The host's answer to an ask: an object, text, or a sentence saying why there is none.
    public struct ModelAnswer: Codable, Sendable, Equatable {
        public var id: Int
        public var object: AgentJSON?
        public var text: String?
        public var error: String?
        public init(id: Int, object: AgentJSON? = nil, text: String? = nil, error: String? = nil) {
            self.id = id; self.object = object; self.text = text; self.error = error
        }
    }

    /// The message's key, as the line names it.
    public var kind: String {
        switch self {
        case .hello: return "hello"
        case .perform: return "perform"
        case .note: return "note"
        case .model: return "model"
        case .answer: return "answer"
        case .output: return "output"
        case .failed: return "failed"
        case .cancel: return "cancel"
        case .entries: return "entries"
        }
    }

    /// Every message's key, in the order a call says them.
    public static let kinds = ["hello", "perform", "note", "model", "answer", "output", "failed", "cancel", "entries"]
}
