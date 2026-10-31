//  WHAT: Agents that live in a runner, as a roster keeps them: each entry an `AnyAgentPackage` (or worker spec)
//        whose call is one `AgentProcess` of the runner, at most its lanes at once, after `check` passes. A host
//        offers them exactly as it offers the packages it links.
//  PIN:  NOTHING RESIDENT. An entry holds a path and a description; a process exists only while a call does.

#if os(macOS)
import Foundation

public enum RemoteAgent {
    /// The roster entries of `executable`, from what it said of itself (`--describe`). Each call checks `check`
    /// first (an installation's tamper check) and tells the host what its process took as its last note.
    public static func entries(_ described: [AgentWire.Entry], executable: URL,
                               environment: [String: String] = ProcessInfo.processInfo.environment,
                               check: @escaping @Sendable () throws -> Void = {}) -> [GraniteRosterEntry] {
        let process = AgentProcess(executable: executable, environment: environment)
        return described.map { entry in
            let lanes = RemoteLanes(limit: entry.lanes ?? 2)
            return entry.rosterEntry { input, host in
                try check()
                return try await lanes.run {
                    try await process.perform(word: entry.word, input: input, host: host, cost: { host.note($0.sentence) })
                }
            }
        }
    }
}
#endif
