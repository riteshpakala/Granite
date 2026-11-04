//  WHAT: An answer held to `granite-answer/1` before it leaves the process: every reserved key in its shape, every
//        file it names among its `paths`, every kind it made or expected one its package declares, every payload a
//        file whose own `schema` says what the answer says. Then stamped with the standard and the agent's word.
//  PIN:  PATHS COMPARED AS FILES. Each path is read against the host's folder (a relative one) and standardized on
//        both sides, so an answer that says `paths` relative and `made` absolute is not refused for it.

import Foundation

public enum AgentAnswerCheck {
    /// Every way `answer` breaks the standard, one sentence each; empty when it keeps it.
    public static func problems(in answer: [String: AgentJSON], word: String, makes: [AgentMake], directory: String?) -> [String] {
        var problems: [String] = []
        for key in AgentAnswerStandard.stamped where answer[key] != nil {
            problems.append("`\(key)` is the runner's to say: an answer does not encode it")
        }
        var paths: Set<String> = []
        switch answer["paths"] {
        case .array(let items)?:
            for item in items {
                if case .string(let path) = item { paths.insert(resolved(path, under: directory)) } else {
                    problems.append("`paths` holds something that is not a path")
                }
            }
        case nil: problems.append("`paths` is missing: an answer names every file it wrote, `[]` when none")
        default: problems.append("`paths` is not a list of paths")
        }
        switch answer["path"] {
        case nil, .null?: break
        case .string(let path)?:
            if !paths.contains(resolved(path, under: directory)) { problems.append("`path` \(path) is not one of `paths`") }
        default: problems.append("`path` is not a path")
        }
        let kinds = Set(makes.map(\.kind))
        let declared = makes.isEmpty ? "declares nothing it makes (`makes`)" : "makes " + makes.map { "`\($0.kind)`" }.joined(separator: ", ")
        problems += list(answer["made"], "made") { item, index in
            var said: [String] = []
            guard let kind = string(item["kind"]), let name = string(item["name"]), !name.isEmpty else {
                return ["`made[\(index)]` needs a `kind` and a `name`"]
            }
            if !kinds.contains(kind) { said.append("`made[\(index)]` is a `\(kind)`, and \(word) \(declared)") }
            let state = string(item["state"]).flatMap(AgentMade.State.init(rawValue:))
            if item["state"] != nil, state == nil {
                said.append("`made[\(index)].state` is one of " + AgentMade.State.allCases.map { "`\($0.rawValue)`" }.joined(separator: ", "))
            }
            let path = string(item["path"])
            if [.written, .rewritten].contains(state ?? .written) {
                if let path {
                    if !paths.contains(resolved(path, under: directory)) { said.append("`made[\(index)]` is in \(path), which is not one of `paths`") }
                } else {
                    said.append("`made[\(index)]` was written, so it names its `path`")
                }
            }
            return said
        }
        problems += list(answer["expected"], "expected") { item, index in
            guard let kind = string(item["kind"]), string(item["name"]) != nil else { return ["`expected[\(index)]` needs a `kind` and a `name`"] }
            return kinds.contains(kind) ? [] : ["`expected[\(index)]` is a `\(kind)`, and \(word) \(declared)"]
        }
        problems += list(answer["problems"], "problems") { item, index in
            guard let kind = string(item["kind"]), string(item["text"]) != nil else { return ["`problems[\(index)]` needs a `kind` and a `text`"] }
            return kind.range(of: #"^[a-z][a-z0-9-]*$"#, options: .regularExpression) == nil ? ["`problems[\(index)].kind` is one lowercase word"] : []
        }
        problems += list(answer["payloads"], "payloads") { item, index in
            guard let path = string(item["path"]), let schema = string(item["schema"]) else { return ["`payloads[\(index)]` needs a `path` and a `schema`"] }
            let file = resolved(path, under: directory)
            if !paths.contains(file) { return ["`payloads[\(index)]` \(path) is not one of `paths`"] }
            guard let data = FileManager.default.contents(atPath: file), case .object(let payload)? = AgentJSON(data: data) else {
                return ["`payloads[\(index)]` \(path) is not a JSON object on disk"]
            }
            let said = string(payload["schema"])
            return said == schema ? [] : ["`payloads[\(index)]` says `\(schema)`, and the file's own `schema` is " + (said.map { "`\($0)`" } ?? "missing")]
        }
        switch answer["notes"] {
        case nil: break
        case .array(let items)? where items.allSatisfy({ if case .string = $0 { return true } else { return false } }): break
        default: problems.append("`notes` is a list of sentences")
        }
        return problems
    }

    /// The answer with the standard's id and the agent's word written in.
    public static func stamped(_ answer: [String: AgentJSON], word: String) -> [String: AgentJSON] {
        var out = answer
        out["format"] = .string(AgentAnswerStandard.format)
        out["agent"] = .object(["word": .string(word)])
        return out
    }

    /// A path as a file: under `directory` when relative (the process's folder when there is none), standardized.
    public static func resolved(_ path: String, under directory: String?) -> String {
        let base = directory ?? FileManager.default.currentDirectoryPath
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent(path)
        return url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func string(_ value: AgentJSON?) -> String? {
        if case .string(let text)? = value { return text }
        return nil
    }

    /// Each item of a reserved list checked by `each`; a key that is not a list of objects is one problem.
    private static func list(_ value: AgentJSON?, _ key: String, _ each: ([String: AgentJSON], Int) -> [String]) -> [String] {
        switch value {
        case nil: return []
        case .array(let items)?:
            return items.enumerated().flatMap { index, item -> [String] in
                guard case .object(let object) = item else { return ["`\(key)[\(index)]` is not an object"] }
                return each(object, index)
            }
        default: return ["`\(key)` is not a list"]
        }
    }
}
