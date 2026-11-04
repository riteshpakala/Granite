import Foundation

/// The `GraniteAgent` a package's run is hosted as. Every call is a run of its own, keyed by the call's id,
/// up to the package's lanes at once; its events and its lifecycle are counted into the package center's
/// state by the engine's one writer, on main.
public struct AgentPackageRun<P: GraniteAgentPackage>: GraniteAgent {
    public typealias Center = AgentPackageCenter<P>
    public typealias Input = AgentPackageCall<P.Input>
    public typealias Event = P.Event
    public typealias Compute = P.Compute

    public static var concurrency: AgentConcurrency { .parallel(max: P.lanes) }
    public static func key(_ input: Input) -> String { input.id }

    private let package = P()

    public init() {}

    /// The package's run, its events passed on and what it throws kept beside the call (`AgentThrown`), so a
    /// refusal keeps its kind past the engine.
    public func run(_ input: Input, context: Context) -> AsyncThrowingStream<P.Event, Error> {
        let inner = package.run(input.input, context: context.hosted(by: input.host))
        let thrown = input.thrown
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in inner { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    thrown.keep(error)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func reduce(state: inout AgentPackageCenter<P>.State, event: P.Event, run: AgentRunID) {
        state.events += 1
    }

    public func reduce(state: inout AgentPackageCenter<P>.State, lifecycle: AgentLifecycle, run: AgentRunID) {
        switch lifecycle {
        case .started: state.runs += 1
        case .finished: state.finished += 1
        case .cancelled: state.cancelled += 1
        case .failed(let message): state.failed += 1; state.lastFailure = message
        }
    }
}
