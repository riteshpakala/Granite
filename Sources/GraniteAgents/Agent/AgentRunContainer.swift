import Foundation
import Granite

/// The compiled half of `@Agent`: what the hosting command keeps. Starts runs, applies the
/// concurrency policy, queues each run's frames and drains them on main into one commit, drops
/// the frames of a run that was superseded, feeds the taps a host reads, and
/// settles the waits `perform` and `wait` open.
///
/// PIN: every entry here is on main — `start`, `cancel`, `drain` — the way a Granite send is;
/// `AgentExecutable` hops before calling. The run's task only ever enqueues.
/// PIN: A WAIT SETTLES AFTER THE STATE IS WRITTEN. A finished run's waiters resume in the drain
/// that committed its lifecycle, after its last frames; a cancelled one's after the `.cancelled`
/// commit. Whoever awaited reads complete state.
final class AgentRunContainer<A: GraniteAgent>: GraniteEventContainer, @unchecked Sendable {
    let id = UUID()
    let label: String
    let reducerType: AnyGraniteReducer.Type? = nil

    private let host: GraniteEventHost
    private let agent = A()
    /// The declaration's policy, else the agent's own.
    private let concurrency: AgentConcurrency
    private let lock = NSLock()
    private var runs: [String: LiveRun] = [:]
    private var waiting: [(run: AgentRunID, input: A.Input)] = []
    private var frames: [String: [Frame]] = [:]
    private var framesSeen: [String: Int] = [:]
    private var drains: Set<String> = []
    private var taps: [String: [AsyncStream<A.Event>.Continuation]] = [:]
    private var slots: [String: Slot] = [:]
    private var cancelledWaits: Set<UUID> = []
    private var counter = 0
    var resolver: (@Sendable (A.Input) async throws -> A.Compute)?

    private enum Frame { case event(A.Event), lifecycle(AgentLifecycle) }

    enum CancelReason { case cancelled, superseded }

    /// PIN: `@unchecked Sendable` because the run's task holds it: `task` is set and read on main,
    /// `context` and `pendingMerges` only under the container's lock.
    private final class LiveRun: @unchecked Sendable {
        let id: AgentRunID
        var task: Task<Void, Never>?
        var context: A.Context?
        /// Inputs merged before the run had its compute: handed to it once it does.
        var pendingMerges: [A.Input] = []
        init(id: AgentRunID) { self.id = id }
    }

    /// Who waits on a run: how many opened a wait, who is suspended, and how it ended once it did.
    private struct Slot {
        var openers = 0
        var waiters: [UUID: CheckedContinuation<AgentOutcome, Error>] = [:]
        var result: Result<AgentOutcome, Error>?
    }

    init(host: GraniteEventHost, label: String, concurrency: AgentConcurrency) {
        self.host = host
        self.label = label
        self.concurrency = concurrency
    }

    /// Granite's own entry: the host's lifecycle (`@Agent(.onTask)`), or `dispatch` by reducer type.
    func fire(_ payload: GranitePayload?) {
        guard let input = A.lifecycleInput else { return }
        onMain { self.start(input) }
    }

    // MARK: - Runs (main)

    func isLive(key: String) -> Bool { lock.withLock { runs[key] != nil } }

    func liveKeys() -> [String] { lock.withLock { Array(runs.keys) + waiting.map(\.run.key) } }

    private func mint(key: String) -> AgentRunID {
        lock.withLock {
            counter += 1
            return AgentRunID(raw: "\(label)-\(counter)", key: key)
        }
    }

    /// Main. Live runs commit `.cancelled`, and so do runs still waiting for a lane.
    ///
    /// PIN: a run asked for and dropped before it started ends as one stopped live would: its
    /// lifecycle commits, its taps end and its waiters fail, under the id it was given when queued.
    func cancel(prefix: String) {
        let (live, dropped): ([String], [AgentRunID]) = lock.withLock {
            let dropped = waiting.filter { $0.run.key.hasPrefix(prefix) }.map(\.run)
            waiting.removeAll { $0.run.key.hasPrefix(prefix) }
            return (runs.keys.filter { $0.hasPrefix(prefix) }, dropped)
        }
        for run in dropped {
            commit(lifecycle: .cancelled, run: run)
            closeTaps(key: run.key)
            settle(run, .failure(CancellationError()))
        }
        for key in live { cancel(key: key) }
    }

    /// Main. Drops one run still waiting for a lane, by its id: it ends as one cancelled live would.
    func cancelQueued(_ run: AgentRunID) {
        let dropped: Bool = lock.withLock {
            guard let index = waiting.firstIndex(where: { $0.run == run }) else { return false }
            waiting.remove(at: index)
            return true
        }
        guard dropped else { return }
        commit(lifecycle: .cancelled, run: run)
        closeTaps(key: run.key)
        settle(run, .failure(CancellationError()))
    }

    @discardableResult
    func start(_ input: A.Input) -> AgentStart {
        let key = A.key(input)
        if let live = lock.withLock({ runs[key] }) {
            switch concurrency {
            case .supersede:
                cancel(key: key, reason: .superseded)
            case .drop:
                return .dropped
            case .merge:
                let context: A.Context? = lock.withLock {
                    if live.context == nil { live.pendingMerges.append(input) }
                    return live.context
                }
                if let context {
                    let agent = self.agent
                    let run = live.id
                    Task { await agent.merge(input, into: run, context: context) }
                }
                return .merged(into: live.id)
            case .parallel:
                // The same key twice is the same run asked for again: the newer one replaces it.
                cancel(key: key, reason: .superseded)
            }
        }
        if case .parallel = concurrency {
            let replaced: AgentRunID? = lock.withLock {
                guard let index = waiting.firstIndex(where: { $0.run.key == key }) else { return nil }
                return waiting.remove(at: index).run
            }
            if let replaced {
                commit(lifecycle: .cancelled, run: replaced)
                closeTaps(key: key)
                settle(replaced, .failure(AgentRunError.superseded(replaced)))
            }
        }
        let run = mint(key: key)
        if case .parallel(let max) = concurrency, let max, lock.withLock({ runs.count }) >= max {
            lock.withLock { waiting.append((run, input)) }
            return .queued(run)
        }
        launch(input, run: run)
        return .started(run)
    }

    func cancel(key: String, reason: CancelReason = .cancelled) {
        guard let live = lock.withLock({ runs.removeValue(forKey: key) }) else { return }
        live.task?.cancel()
        // Said now, on main, before any late frame could: the run is over for the state and
        // for whoever was listening. Frames it still enqueues are dropped (`drain` checks).
        lock.withLock {
            frames.removeValue(forKey: live.id.raw)
            framesSeen.removeValue(forKey: live.id.raw)
        }
        commit(lifecycle: .cancelled, run: live.id)
        closeTaps(key: key)
        settle(live.id, .failure(reason == .superseded ? AgentRunError.superseded(live.id) : CancellationError()))
        startWaiting()
    }

    private func launch(_ input: A.Input, run runID: AgentRunID) {
        let live = LiveRun(id: runID)
        lock.withLock { runs[runID.key] = live }
        commit(lifecycle: .started, run: runID)
        let resolver = self.resolver
        let agent = self.agent
        let scope = AgentRunScope.Current(run: runID, agent: ObjectIdentifier(A.self))
        let deliver: @Sendable (A.Event) -> Void = { [weak self] event in self?.enqueue(.event(event), run: runID) }
        live.task = Task(priority: .userInitiated) { [weak self] in
            let outcome: AgentLifecycle = await AgentRunScope.$current.withValue(scope) {
                do {
                    guard let resolver else { throw AgentRunError.noCompute(String(describing: A.self)) }
                    let compute = try await resolver(input)
                    let context = A.Context(run: runID, compute: compute, isCancelled: { Task.isCancelled }, deliver: deliver)
                    let merges: [A.Input] = self?.lock.withLock {
                        live.context = context
                        defer { live.pendingMerges = [] }
                        return live.pendingMerges
                    } ?? []
                    for merged in merges { Task { await agent.merge(merged, into: runID, context: context) } }
                    var ended: AgentLifecycle = .finished
                    for try await event in agent.run(input, context: context) {
                        if Task.isCancelled { ended = .cancelled; break }
                        deliver(event)
                    }
                    return Task.isCancelled ? .cancelled : ended
                } catch is CancellationError {
                    return .cancelled
                } catch {
                    return Task.isCancelled ? .cancelled : .failed("\(error)")
                }
            }
            self?.enqueue(.lifecycle(outcome), run: runID)
        }
    }

    private func startWaiting() {
        guard case .parallel(let max) = concurrency else { return }
        let next: (run: AgentRunID, input: A.Input)? = lock.withLock {
            guard max.map({ runs.count < $0 }) ?? true, !waiting.isEmpty else { return nil }
            return waiting.removeFirst()
        }
        if let next { launch(next.input, run: next.run) }
    }

    // MARK: - Frames (any thread in, main out)

    private func enqueue(_ frame: Frame, run: AgentRunID) {
        let schedule: Bool = lock.withLock {
            frames[run.raw, default: []].append(frame)
            return drains.insert(run.raw).inserted
        }
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in self?.drain(run) }
    }

    private func drain(_ run: AgentRunID) {
        let pending: [Frame] = lock.withLock {
            drains.remove(run.raw)
            return frames.removeValue(forKey: run.raw) ?? []
        }
        guard !pending.isEmpty else { return }
        // A frame of a run that was superseded or cancelled is dropped: its state is gone.
        guard lock.withLock({ runs[run.key]?.id == run }) else { return }
        var events: [A.Event] = []
        var seen = 0
        var ended: AgentLifecycle?
        for frame in pending {
            switch frame {
            case .event(let event):
                seen += 1
                if let last = events.last, let one = A.coalesce(last, event) { events[events.count - 1] = one } else { events.append(event) }
            case .lifecycle(let lifecycle):
                ended = lifecycle
            }
        }
        lock.withLock { framesSeen[run.raw, default: 0] += seen }
        let taps = lock.withLock { self.taps[run.key] ?? [] }
        for event in events { for tap in taps { tap.yield(event) } }
        if var state = host.state() as? A.Center.GenericGraniteState {
            for event in events { agent.reduce(state: &state, event: event, run: run) }
            if let ended { agent.reduce(state: &state, lifecycle: ended, run: run) }
            host.commit(state)
        }
        guard let ended else { return }
        lock.withLock { if runs[run.key]?.id == run { runs.removeValue(forKey: run.key) } }
        closeTaps(key: run.key)
        startWaiting()
        let count = lock.withLock { framesSeen.removeValue(forKey: run.raw) ?? 0 }
        switch ended {
        case .finished, .started: settle(run, .success(AgentOutcome(run: run, frames: count)))
        case .failed(let message): settle(run, .failure(AgentRunError.failed(run, message)))
        case .cancelled: settle(run, .failure(CancellationError()))
        }
    }

    private func commit(lifecycle: AgentLifecycle, run: AgentRunID) {
        guard var state = host.state() as? A.Center.GenericGraniteState else { return }
        agent.reduce(state: &state, lifecycle: lifecycle, run: run)
        host.commit(state)
    }

    // MARK: - Waits

    /// Main. Opens a wait on `run` so a settle that lands before the waiter suspends is kept.
    private func open(_ run: AgentRunID) {
        lock.withLock { slots[run.raw, default: Slot()].openers += 1 }
    }

    private func settle(_ run: AgentRunID, _ result: Result<AgentOutcome, Error>) {
        let resumed: [CheckedContinuation<AgentOutcome, Error>] = lock.withLock {
            guard var slot = slots[run.raw] else { return [] }
            let waiters = Array(slot.waiters.values)
            slot.waiters = [:]
            slot.openers -= waiters.count
            slot.result = result
            slots[run.raw] = slot.openers > 0 ? slot : nil
            return waiters
        }
        for waiter in resumed { waiter.resume(with: result) }
    }

    /// Suspends on an opened wait until the run settles.
    private func suspend(on run: AgentRunID, onCancel: @escaping @Sendable () -> Void) async throws -> AgentOutcome {
        let token = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AgentOutcome, Error>) in
                let now: Result<AgentOutcome, Error>? = lock.withLock {
                    guard var slot = slots[run.raw] else { return .failure(AgentRunError.unknownRun(run)) }
                    if let result = slot.result {
                        slot.openers -= 1
                        slots[run.raw] = slot.openers > 0 ? slot : nil
                        return result
                    }
                    if cancelledWaits.remove(token) != nil {
                        slot.openers -= 1
                        slots[run.raw] = slot.openers > 0 ? slot : nil
                        return .failure(CancellationError())
                    }
                    slot.waiters[token] = continuation
                    slots[run.raw] = slot
                    return nil
                }
                if let now { continuation.resume(with: now) }
            }
        } onCancel: {
            // This waiter only: a cancelled caller stops waiting; whether the run stops is `onCancel`'s.
            let mine: CheckedContinuation<AgentOutcome, Error>? = self.lock.withLock {
                guard var slot = self.slots[run.raw], let waiter = slot.waiters.removeValue(forKey: token) else {
                    self.cancelledWaits.insert(token)
                    return nil
                }
                slot.openers -= 1
                self.slots[run.raw] = slot.openers > 0 || !slot.waiters.isEmpty ? slot : nil
                return waiter
            }
            mine?.resume(throwing: CancellationError())
            onCancel()
        }
    }

    func perform(_ input: A.Input) async throws -> AgentOutcome {
        if let scope = AgentRunScope.current, scope.agent == ObjectIdentifier(A.self), scope.run.key == A.key(input) {
            throw AgentRunError.reentrant(scope.run)
        }
        // One main turn opens the wait and starts the run, so no frame can land between the two.
        let (run, owned): (AgentRunID, Bool) = try await withCheckedThrowingContinuation { continuation in
            onMain {
                switch self.start(input) {
                case .started(let run), .queued(let run):
                    self.open(run)
                    continuation.resume(returning: (run, true))
                case .merged(let run):
                    self.open(run)
                    continuation.resume(returning: (run, false))
                case .dropped:
                    continuation.resume(throwing: AgentRunError.dropped(self.label))
                }
            }
        }
        return try await suspend(on: run) { [weak self] in
            guard owned, let self else { return }
            onMain {
                let live = self.lock.withLock { self.runs[run.key]?.id == run }
                if live { self.cancel(key: run.key) } else { self.cancelQueued(run) }
            }
        }
    }

    func wait(run: AgentRunID) async throws -> AgentOutcome {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            onMain {
                let known = self.lock.withLock {
                    self.slots[run.raw] != nil || self.runs[run.key]?.id == run || self.waiting.contains { $0.run == run }
                }
                guard known else { return continuation.resume(throwing: AgentRunError.unknownRun(run)) }
                self.open(run)
                continuation.resume()
            }
        }
        return try await suspend(on: run) {}
    }

    func wait(prefix: String) async {
        let opened: [AgentRunID] = await withCheckedContinuation { continuation in
            onMain {
                let runs: [AgentRunID] = self.lock.withLock {
                    self.runs.values.map(\.id).filter { $0.key.hasPrefix(prefix) } + self.waiting.map(\.run).filter { $0.key.hasPrefix(prefix) }
                }
                for run in runs { self.open(run) }
                continuation.resume(returning: runs)
            }
        }
        for run in opened { _ = try? await suspend(on: run) {} }
    }

    // MARK: - Taps

    /// Every event of the run with `key`, before it is reduced, until the run ends.
    func events(key: String) -> AsyncStream<A.Event> {
        AsyncStream { continuation in
            lock.withLock { taps[key, default: []].append(continuation) }
        }
    }

    private func closeTaps(key: String) {
        let open = lock.withLock { taps.removeValue(forKey: key) ?? [] }
        for tap in open { tap.finish() }
    }
}
