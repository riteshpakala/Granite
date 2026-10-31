import Foundation
import Granite

/// A package agent's center, hosted without SwiftUI and kept for the life of the process, with the compute
/// its runs share attached once.
///
/// PIN: made on main, where a hosted command compiles its events, and found through one registry by the
/// package's type, so every call of a package runs on the same center and shares one compute.
/// PIN: `@unchecked Sendable` because the command is touched on main only; what crosses threads is the
/// executable, which is safe from any.
final class AgentPackageHost<P: GraniteAgentPackage>: @unchecked Sendable {
    let command: GraniteCommand<AgentPackageCenter<P>>
    let executable: AgentExecutable<AgentPackageRun<P>>

    @MainActor
    private init() {
        command = .hosted()
        executable = command.center.$agent
        let compute = AgentPackageCompute<P>()
        executable.attach { _ in try await compute.value() }
    }

    /// The host of `P`, made on its first call.
    @MainActor
    static func shared() -> AgentPackageHost<P> {
        let key = String(reflecting: P.self)
        if let host = packageHosts.get(key) as? AgentPackageHost<P> { return host }
        let host = AgentPackageHost<P>()
        packageHosts.put(key, host)
        return host
    }
}

/// Every package host this process made, by package type.
private let packageHosts = TransientRegistry<AnyObject>()
