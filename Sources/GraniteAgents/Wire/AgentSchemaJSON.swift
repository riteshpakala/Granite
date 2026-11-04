//  WHAT: The machine-readable half of the standard (`Schema/GraniteAgent.md`), as JSON Schema: an agent's entry,
//        every message of the wire, an installation's record, and a package call's answer (`granite-answer/1`). `Schema/granite-agent-*.schema.json` are these
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
            "makes": described(["type": "array", "items": ["$ref": "#/$defs/make"]], "what it makes, each kind with where it lands"),
            "toolNames": ["type": "array", "items": string],
            "budget": ["type": "string", "enum": WorkerBudget.allCases.map(\.rawValue)],
            "shell": ["type": "boolean"],
            "reportRule": string,
        ],
    ]

    nonisolated(unsafe) static let make: [String: Any] = [
        "type": "object", "required": ["kind", "what", "into"],
        "properties": [
            "kind": described(["type": "string", "pattern": "^[a-z][a-z0-9-]*$"], "the kind a call's made and expected items carry"),
            "what": described(string, "what it is, in the words a reading can match to a request"),
            "into": described(["type": "array", "items": string], "where it writes, relative to the host's folder; * is one path component"),
            "never": described(string, "what it never does"),
        ],
    ]

    nonisolated(unsafe) static let refusal: [String: Any] = [
        "type": "object", "required": ["kind", "reasons"],
        "properties": [
            "kind": ["type": "string", "enum": AgentRefusal.Kind.allCases.map(\.rawValue)],
            "reasons": described(["type": "array", "items": string], "one sentence each, its fix in it"),
        ],
    ]

    nonisolated(unsafe) static let answerObject: [String: Any] = [
        "type": "object", "required": ["format", "agent", "paths"],
        "description": "the reserved keys of a package call's answer; every other key is the package's own",
        "properties": [
            "format": ["const": AgentAnswerStandard.format],
            "agent": ["type": "object", "required": ["word"], "properties": ["word": string]],
            "path": described(["type": ["string", "null"]], "the first file it wrote"),
            "paths": described(["type": "array", "items": string], "every file it wrote or removed, absolute or relative to the host's folder"),
            "notes": described(["type": "array", "items": string], "what the model should know, one sentence each"),
            "made": ["type": "array", "items": [
                "type": "object", "required": ["kind", "name"],
                "properties": ["kind": string, "name": string, "path": string,
                               "state": ["type": "string", "enum": AgentMade.State.allCases.map(\.rawValue)]],
            ]],
            "expected": described(["type": "array", "items": ["type": "object", "required": ["kind", "name"],
                                                              "properties": ["kind": string, "name": string]]],
                                  "what the call asked for, as the package read it"),
            "problems": described(["type": "array", "items": ["type": "object", "required": ["kind", "text"],
                                                              "properties": ["kind": string, "text": string]]],
                                  "what the call could only do in part; not a refusal"),
            "payloads": described(["type": "array", "items": ["type": "object", "required": ["path", "schema"],
                                                              "properties": ["path": string, "schema": described(string, "the id the file's own schema key says")]]],
                                  "files among paths that follow a standard of their own"),
        ],
    ]

    static var definitions: [String: Any] {
        ["schema": schemaForm, "field": field, "entry": entryObject, "make": make, "refusal": refusal, "answer": answerObject]
    }

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
            "properties": ["wire": ["type": "string", "pattern": "^granite-agent/[0-9]+$"], "pid": integer,
                           "answer": described(string, "the answer standard its calls keep, granite-answer/1")],
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
                message("output", described(["type": "object"], "a granite-answer/1 answer from a package whose Output keeps it, else its own JSON"),
                        "agent → host, last: the call's output"),
                ["type": "object", "required": ["failed"], "description": "agent → host, last: why the call failed, and when it was refused, how",
                 "properties": ["failed": described(string, "the sentence"), "refused": ["$ref": "#/$defs/refusal"]]],
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

    /// A package call's answer, `granite-answer/1`: the keys a host reads.
    public static var answer: [String: Any] {
        ["$schema": "https://json-schema.org/draft/2020-12/schema", "$id": base + "granite-agent-answer.schema.json",
         "title": "A package call's answer (\(AgentAnswerStandard.format))", "$ref": "#/$defs/answer", "$defs": definitions]
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
         "granite-agent-installation.schema.json": data(installation), "granite-agent-answer.schema.json": data(answer)]
    }
}
