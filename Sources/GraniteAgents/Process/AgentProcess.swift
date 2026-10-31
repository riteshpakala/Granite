//  WHAT: The host's side of `granite-agent/1`: one call to an agent in a process of its own. The runner is
//        spawned, handed the call, its notes passed to the host and its asks answered by the host's model, its
//        output taken, and the process reaped, with what it took measured.
//  PIN:  ONE PROCESS, ONE CALL, THEN RELEASED. Nothing of a call outlives it: the GPU device, the web page, the
//        model's asks are the process's, and the process is gone when the answer is in. A call that will not
//        end is ended: cancelling sends `cancel` and SIGTERM to its group, and SIGKILL follows the grace.

#if os(macOS)
import Foundation

public struct AgentProcess: Sendable {
    public let executable: URL
    public let environment: [String: String]

    public init(executable: URL, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.executable = executable
        var environment = environment
        environment["GRANITE_AGENT"] = "1"
        self.environment = environment
    }

    /// What the executable carries, as `--describe` says it: nothing is made to say it.
    public func describe() async throws -> [AgentWire.Entry] {
        let child = try AgentChild(executable: executable, arguments: ["--describe"], directory: nil, environment: environment)
        child.channel.close()
        for await message in child.channel.messages {
            if case .entries(let entries) = message {
                _ = await child.exited()
                return entries
            }
        }
        let ended = await child.exited()
        throw AgentRemoteError.ended(word: executable.lastPathComponent, status: AgentChild.describe(ended.status), log: child.log)
    }

    /// One call to `word` in a process of its own, its notes and asks served from `host`; `cost` hears what the
    /// process took once it is reaped. Cancelling the awaiting task ends the process.
    public func perform(word: String, input: Data, host: AgentHost,
                        cost: (@Sendable (AgentProcessCost) -> Void)? = nil) async throws -> Data {
        guard let json = AgentJSON(data: input) else { throw AgentRemoteError.unreadable(word: word, reason: "the input is not JSON") }
        let directory = host.directory.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let child = try AgentChild(executable: executable, arguments: [], directory: directory, environment: environment)
        let call = AgentWire.Perform(word: word, input: json, directory: host.directory, ask: host.ask, model: host.model != nil)
        let result = await withTaskCancellationHandler {
            await Self.serve(child, word: word, call: call, host: host)
        } onCancel: {
            try? child.channel.send(.cancel)
            child.terminate()
        }
        // The call is over: its stdin ends, and a process that answered exits at once. One that does not is ended.
        child.channel.close()
        let stragglers = DispatchWorkItem { child.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: stragglers)
        let ended = await child.exited()
        stragglers.cancel()
        cost?(child.cost(ended))
        switch result {
        case .success(let data):
            return data
        case .failure(let error):
            if Task.isCancelled { throw CancellationError() }
            if case AgentRemoteError.ended = error {
                throw AgentRemoteError.ended(word: word, status: AgentChild.describe(ended.status), log: child.log)
            }
            throw error
        }
    }

    private static func serve(_ child: AgentChild, word: String, call: AgentWire.Perform, host: AgentHost) async -> Result<Data, Error> {
        var sent = false
        var asks: [Task<Void, Never>] = []
        defer { asks.forEach { $0.cancel() } }
        for await message in child.channel.messages {
            switch message {
            case .hello(let hello):
                guard hello.wire.hasPrefix("granite-agent/"), Int(hello.wire.split(separator: "/").last ?? "") == AgentWire.major else {
                    return .failure(AgentRemoteError.unreadable(word: word, reason: "it speaks \(hello.wire), and this host \(AgentWire.version)"))
                }
                guard !sent else { continue }
                sent = true
                do { try child.channel.send(.perform(call)) } catch {
                    return .failure(AgentRemoteError.unreadable(word: word, reason: "the call could not be sent: \(error)"))
                }
            case .note(let line):
                host.note(line)
            case .model(let ask):
                asks.append(Task {
                    let answer = await Self.answer(ask, host: host)
                    try? child.channel.send(.answer(answer))
                })
            case .output(let json):
                return .success(json.data())
            case .failed(let message):
                return .failure(AgentRemoteError.failed(word: word, message: message))
            default:
                return .failure(AgentRemoteError.unreadable(word: word, reason: "it said `\(message.kind)` during a call"))
            }
        }
        return .failure(AgentRemoteError.ended(word: word, status: "", log: ""))
    }

    /// The host's model's answer to one ask, or a sentence saying why there is none.
    static func answer(_ ask: AgentWire.ModelAsk, host: AgentHost) async -> AgentWire.ModelAnswer {
        guard let model = host.model else { return .init(id: ask.id, error: "this host has no model loaded") }
        do {
            switch ask.kind {
            case .object:
                let data = try await model.object(schema: ask.schema?.data() ?? Data("{}".utf8), system: ask.system, user: ask.user,
                                                  maxTokens: ask.maxTokens, seconds: ask.seconds)
                guard let object = AgentJSON(data: data) else { return .init(id: ask.id, error: "the model's answer is not JSON") }
                return .init(id: ask.id, object: object)
            case .text:
                return .init(id: ask.id, text: try await model.text(system: ask.system, user: ask.user, maxTokens: ask.maxTokens, seconds: ask.seconds))
            }
        } catch {
            return .init(id: ask.id, error: "\(error)")
        }
    }
}
#endif
