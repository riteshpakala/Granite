import Foundation

/// What installing an agent package can say instead of an installation.
public enum AgentInstallError: Error, Equatable, CustomStringConvertible {
    case toolchain(String)
    case fetch(source: String, reason: String)
    case notAPackage(source: String, reason: String)
    case notGranite(name: String)
    case build(name: String, log: String, path: String)
    case noAgent(name: String)
    case clash(word: String, installed: String)
    case notInstalled(String)

    public var description: String {
        switch self {
        case .toolchain(let reason): return "a Swift toolchain is needed to build an agent: \(reason)"
        case .fetch(let source, let reason): return "could not fetch \(source): \(reason)"
        case .notAPackage(let source, let reason): return "\(source) is not a Swift package: \(reason)"
        case .notGranite(let name): return "\(name) does not depend on Granite, so it carries no Granite agent"
        case .build(let name, let log, let path): return "\(name) did not build (the whole log is at \(path)):\n\(log)"
        case .noAgent(let name): return "\(name) holds no agent: no GraniteAgentPackage or GraniteWorkerSpec record"
        case .clash(let word, let installed): return "an agent called `\(word)` is already installed, from \(installed)"
        case .notInstalled(let name): return "no agent installed here is called \(name)"
        }
    }
}
