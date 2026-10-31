import Foundation

/// One agent a roster holds: a package agent, which an app runs by its word, or a worker spec, which an app
/// makes one of its worker kinds.
public enum GraniteRosterEntry: Sendable {
    case package(AnyAgentPackage)
    case worker(AnyWorkerSpec)

    public var word: String {
        switch self {
        case .package(let package): return package.word
        case .worker(let worker): return worker.word
        }
    }

    /// The module that declares it.
    public var module: String {
        switch self {
        case .package(let package): return package.module
        case .worker(let worker): return worker.module
        }
    }
}
