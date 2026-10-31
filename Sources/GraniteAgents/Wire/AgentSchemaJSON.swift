//  WHAT: The machine-readable half of the standard (`Schema/GraniteAgent.md`), as JSON Schema: an agent's entry,
//        every message of the wire, and an installation's record. `Schema/granite-agent-*.schema.json` are these
//        documents, and a test fails when the committed files and the code drift apart.

import Foundation

public enum AgentSchemaJSON {
    static let base = "https://github.com/riteshpakala/Granite/blob/main/Schema/"
    nonisolated(unsafe) static let string: [String: Any] = ["type": "string"]
    nonisolated(unsafe) static let integer: [String: Any] = ["type": "integer"]

    static func described(_ value: [String: Any], _ description: String) -> [String: Any] {
        value.merging(["description": description]) { _, new in new }
    }

    /// An input's schema in its data form (`GraniteSchema`'s Codable form), recursive.
    nonisolated(unsafe) static let schemaForm: [String: Any] = [
        "description": "an agent's input schema as data: a word for a scalar or `any`, else exactly one of choice, array, object",
        "oneOf": [
            ["type": "string", "enum": ["string", "integer", "number", "boolean", "any"]],
            ["type": "object", "required": ["choice"], "properties": ["choice": ["type": "array", "items": string]]],
            ["type": "object", "required": ["array"], "properties": ["array": ["$ref": "#/$defs/schema"]]],
            ["type": "object", "required": ["object"], "properties": ["object": ["type": "array", "items": ["$ref": "#/$defs/field"]]]],
        ],
    ]

    nonisolated(unsafe) static let field: [String: Any] = [
        "type": "object",
        "required": ["name", "schema", "required"],
        "properties": ["name": string, "schema": ["$ref": "#/$defs/schema"], "required": ["type": "boolean"]],
    ]

    nonisolated(unsafe) static let entryObject: [String: Any] = [
        "type": "object",
        "required": ["kind", "word", "summary", "module", "type"],
        "properties": [
            "kind": ["type": "string", "enum": ["package", "worker"]],
            "word": described(["type": "string", "pattern": "^[a-z][a-z0-9-]*$"], "how a host calls it and a model names it: lowercase, one word"),
            "summary": described(string, "what it does, in one sentence"),
            "module": described(string, "the module that declares it"),
            "type": described(string, "its type, as Module.Type"),
            "schema": ["$ref": "#/$defs/schema"],
            "fields": described(["type": "object", "additionalProperties": string], "a note beside each input field"),
            "lanes": described(["type": "integer", "minimum": 1], "how many calls run at once"),
            "guide": described(string, "how to use it well, in its own words"),
            "toolNames": ["type": "array", "items": string],
            "budget": ["type": "string", "enum": WorkerBudget.allCases.map(\.rawValue)],
            "shell": ["type": "boolean"],
            "reportRule": string,
        ],
    ]

    static var definitions: [String: Any] { ["schema": schemaForm, "field": field, "entry": entryObject] }

    /// One agent, described: what `--describe` prints and an installation keeps.
    public static var entry: [String: Any] {
        ["$schema": "https://json-schema.org/draft/2020-12/schema", "$id": base + "granite-agent-entry.schema.json",
         "title": "A Granite agent, described (granite-agent/1)", "$ref": "#/$defs/entry", "$defs": definitions]
    }

    /// Every message of `granite-agent/1`, one per line.
    public static var wire: [String: Any] {
        let ask: [String: Any] = [
            "type": "object", "required": ["id", "kind", "system", "user", "maxTokens", "seconds"],
            "properties": ["id": integer, "kind": ["type": "string", "enum": ["object", "text"]],
                           "schema": described(["type": "object"], "JSON Schema, for an object"), "system": string, "user": string,
                           "maxTokens": integer, "seconds": ["type": "number"]],
        ]
        let answer: [String: Any] = [
            "type": "object", "required": ["id"],
            "properties": ["id": integer, "object": [String: Any](), "text": string, "error": described(string, "why there is no answer")],
        ]
        let perform: [String: Any] = [
            "type": "object", "required": ["word", "input", "model"],
            "properties": ["word": string, "input": described([String: Any](), "the call's input, as its schema says"),
                           "directory": string, "ask": described(string, "what the person asked, in their words"),
                           "model": described(["type": "boolean"], "whether the host offers its model")],
        ]
        let hello: [String: Any] = [
            "type": "object", "required": ["wire"],
            "properties": ["wire": ["type": "string", "pattern": "^granite-agent/[0-9]+$"], "pid": integer],
        ]
        func message(_ key: String, _ value: [String: Any], _ description: String) -> [String: Any] {
            ["type": "object", "required": [key], "properties": [key: value], "description": description]
        }
        return [
            "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": base + "granite-agent-wire.schema.json",
            "title": "A message of granite-agent/1: one JSON object on one line, one key naming it",
            "oneOf": [
                message("hello", hello, "agent → host, first: what it speaks and which process it is"),
                message("perform", perform, "host → agent: the one call the process answers"),
                message("note", string, "agent → host: a line of progress"),
                message("model", ask, "agent → host: an ask of the host's model"),
                message("answer", answer, "host → agent: the answer to an ask, by its id"),
                message("output", [String: Any](), "agent → host, last: the call's output"),
                message("failed", string, "agent → host, last: why the call failed"),
                message("cancel", ["type": "object"], "host → agent: end the call"),
                message("entries", ["type": "array", "items": ["$ref": "#/$defs/entry"]], "agent → host, with --describe: what it carries"),
            ],
            "$defs": definitions,
        ]
    }

    /// An installed runner's record, `installation.json`.
    public static var installation: [String: Any] {
        [
            "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": base + "granite-agent-installation.schema.json",
            "title": "An installed Granite agent runner (installation.json)",
            "type": "object",
            "required": ["format", "name", "source", "executable", "sha256", "size", "builtAt", "entries"],
            "properties": [
                "format": ["const": AgentInstallation.format],
                "name": described(string, "the package's name, and its folder's on the shelf"),
                "source": ["oneOf": [
                    ["type": "object", "required": ["url"], "properties": ["url": string, "revision": string]],
                    ["type": "object", "required": ["path"], "properties": ["path": string]],
                ]],
                "revision": described(string, "the source's commit"),
                "granite": described(string, "the Granite revision the runner was built against"),
                "executable": described(string, "relative to the installation's folder"),
                "sha256": ["type": "string", "pattern": "^[0-9a-f]{64}$"],
                "size": integer,
                "modified": described(["type": "number"], "the executable's modification time when installed, seconds since 1970"),
                "builtAt": ["type": "string", "format": "date-time"],
                "entries": ["type": "array", "items": ["$ref": "#/$defs/entry"]],
            ],
            "$defs": definitions,
        ]
    }

    /// A document as the committed file holds it: sorted, indented, one trailing newline.
    public static func data(_ document: [String: Any]) -> Data {
        var data = (try? JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
            ?? Data("{}".utf8)
        data.append(0x0A)
        return data
    }

    /// The committed files, by name.
    public static var files: [String: Data] {
        ["granite-agent-entry.schema.json": data(entry), "granite-agent-wire.schema.json": data(wire),
         "granite-agent-installation.schema.json": data(installation)]
    }
}
