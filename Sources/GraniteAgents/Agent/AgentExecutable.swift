import Foundation
import Granite

/// What `@Agent var chat: Chat.Agent` holds and `$chat` projects: the handle a reducer, a root,
/// a view or a command line starts runs through, awaits, cancels, taps, and attaches compute to.
///
/// Two ways to start a run, the two a reducer has:
/// - `send` (asynchronous): the run begins; its frames are reduced on later main turns by the
///   agent's own `reduce`. A reducer's effect calls it and its scope ends.
/// - `perform` (synchronous for the caller): the run begins and the call returns once its
///   lifecycle has been reduced and committed after its last frames, so the state read next is
///   complete. A reducer's effect awaits it, then writes through its service's writer and resolves its ticket.
public final class AgentExecutable<A: GraniteAgent>: @unchecked Sendable {
    /// The declaration's policy; nil means the agent's own `A.concurrency`.
    public let concurrency: AgentConcurrency?
    private let lock = NSLock()
    private var container: AgentRunContainer<A>?
    private var resolver: (@Sendable (A.Input) async throws -> A.Compute)?

    public init(concurrency: AgentConcurrency? = nil) {
        self.concurrency = concurrency
    }

    private var label: String { String(describing: A.self) }

    /// The composition root supplies what a run computes with, from its input.
    public func attach(_ resolve: @escaping @Sendable (A.Input) async throws -> A.Compute) {
        lock.withLock {
            resolver = resolve
            container?.resolver = resolve
        }
    }

    /// Starts a run (or merges, drops, queues, by the policy). From any thread: an off-main send hops.
    public func send(_ input: A.Input) {
        guard let container = lock.withLock({ container }) else {
            FileHandle.standardError.write(Data("\(label) sent before its center compiled; dropped\n".utf8))
            return
        }
        onMain { container.start(input) }
    }

    /// Main-only. Starts a run and says what happened, with the run's id.
    @discardableResult
    public func start(_ input: A.Input) -> AgentStart {
        guard let container = lock.withLock({ container }) else {
            FileHandle.standardError.write(Data("\(label) started before its center compiled; dropped\n".utf8))
            return .dropped
        }
        return container.start(input)
    }

    /// Starts the run (or merges into the live one) and suspends until its lifecycle has been
    /// reduced and committed after its last frames. Throws `CancellationError` when the run is
    /// cancelled, `AgentRunError.superseded` when a later send took its key, `.failed` with the
    /// lifecycle's message, `.dropped` under `.drop`, `.reentrant` from inside its own run.
    /// Cancelling the awaiting task cancels a run it started or queued, never one it merged into.
    public func perform(_ input: A.Input) async throws -> AgentOutcome {
        guard let container = lock.withLock({ container }) else { throw AgentRunError.notCompiled(label) }
        return try await container.perform(input)
    }

    /// Waits on a run someone else started. Throws `.unknownRun` once the run has ended and no wait
    /// was open: start it with `start` and wait in the same main turn, or tap `events(key:)`.
    public func wait(run: AgentRunID) async throws -> AgentOutcome {
        guard let container = lock.withLock({ container }) else { throw AgentRunError.notCompiled(label) }
        return try await container.wait(run: run)
    }

    /// Returns when every run whose key starts with `prefix`, live or waiting, has ended, however
    /// it ended.
    public func wait(prefix: String) async {
        guard let container = lock.withLock({ container }) else { return }
        await container.wait(prefix: prefix)
    }

    /// Cancels the live run with `key`, committing `.cancelled` at once.
    public func cancel(key: String = AgentRunID.defaultKey) {
        guard let container = lock.withLock({ container }) else { return }
        onMain { container.cancel(key: key) }
    }

    public func isLive(key: String = AgentRunID.defaultKey) -> Bool {
        lock.withLock { container }?.isLive(key: key) ?? false
    }

    /// The keys of every run that is live or waiting for a lane.
    public func liveKeys() -> [String] {
        lock.withLock { container }?.liveKeys() ?? []
    }

    /// Cancels every run whose key starts with `prefix`, and drops those still waiting: everything one
    /// session started, when its key is `session/…`.
    public func cancel(prefix: String) {
        guard let container = lock.withLock({ container }) else { return }
        onMain { container.cancel(prefix: prefix) }
    }

    /// Every event of the run with `key`, as it streams and before it is reduced, until the run
    /// ends: what a host renders and records.
    public func events(key: String = AgentRunID.defaultKey) -> AsyncStream<A.Event> {
        guard let container = lock.withLock({ container }) else { return AsyncStream { $0.finish() } }
        return container.events(key: key)
    }

    func compile(with host: GraniteEventHost) -> AgentRunContainer<A> {
        lock.withLock {
            if let container { return container }
            let made = AgentRunContainer<A>(host: host, label: label, concurrency: concurrency ?? A.concurrency)
            made.resolver = resolver
            container = made
            return made
        }
    }
}
