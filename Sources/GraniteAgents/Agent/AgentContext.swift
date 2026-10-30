import Foundation

/// What a run computes with and how it reaches the world: its id, its compute, cancellation,
/// and `spawn`, which runs a child agent inside this run and streams the child's frames into
/// this run's own events.
public struct AgentContext<Compute: Sendable, Event: Sendable>: Sendable {
    public let run: AgentRunID
    public let compute: Compute
    public let isCancelled: @Sendable () -> Bool
    /// Delivers an event into this run's stream, as `run` itself would.
    public let deliver: @Sendable (Event) -> Void

    public init(run: AgentRunID, compute: Compute, isCancelled: @escaping @Sendable () -> Bool, deliver: @escaping @Sendable (Event) -> Void) {
        self.run = run; self.compute = compute; self.isCancelled = isCancelled; self.deliver = deliver
    }

    /// Runs `child` and returns its frames — announced, each event, how it ended — mapped into this
    /// run's events, for this run to yield in its own order. Ordering is the parent's: a frame the
    /// parent yields before iterating the child comes first, which is why the child's frames are
    /// not delivered behind the parent's back. Cancelling the parent cancels the child; a child the
    /// map turns into nothing leaves no trace.
    public func spawn<Child: GraniteAgent>(_ child: Child, input: Child.Input, compute: Child.Compute,
                                           id: String, kind: String, prompt: String,
                                           map: @escaping @Sendable (ChildFrame<Child.Event>) -> Event?) -> AsyncStream<Event> {
        let childRun = AgentRunID(raw: id, key: Child.key(input), parent: run.raw)
        let parentCancelled = isCancelled
        return AsyncStream { continuation in
            if let announced = map(.started(childRun, kind: kind, prompt: prompt)) { continuation.yield(announced) }
            let task = Task {
                let context = AgentContext<Child.Compute, Child.Event>(
                    run: childRun, compute: compute, isCancelled: { Task.isCancelled || parentCancelled() },
                    deliver: { event in if let mapped = map(.event(childRun, event)) { continuation.yield(mapped) } })
                var outcome: AgentLifecycle = .finished
                do {
                    for try await event in child.run(input, context: context) {
                        if Task.isCancelled || parentCancelled() { outcome = .cancelled; break }
                        if let mapped = map(.event(childRun, event)) { continuation.yield(mapped) }
                    }
                    if Task.isCancelled || parentCancelled() { outcome = .cancelled }
                } catch is CancellationError {
                    outcome = .cancelled
                } catch {
                    outcome = Task.isCancelled ? .cancelled : .failed("\(error)")
                }
                if let ended = map(.finished(childRun, outcome)) { continuation.yield(ended) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
