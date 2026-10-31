import Foundation

/// What every run of a package computes with, made by the package once, on the first call. A make that
/// fails is tried again by the next call.
actor AgentPackageCompute<P: GraniteAgentPackage> {
    private var making: Task<P.Compute, Error>?

    func value() async throws -> P.Compute {
        if let making { return try await making.value }
        let task = Task { try await P.compute() }
        making = task
        do {
            return try await task.value
        } catch {
            if making == task { making = nil }
            throw error
        }
    }
}
