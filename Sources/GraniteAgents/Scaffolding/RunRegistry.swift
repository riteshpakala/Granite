//  WHAT: Cancellable work by id. A Granite effect's `.run` hands out no Task and nothing cancels an
//        in-flight reducer, so long work makes its own Task and registers it here, and a `Cancel`
//        reducer cancels it.
//  PIN:  A cancel that arrives before the register leaves a tombstone: `register` then returns false
//        and the caller cancels its Task at once. `finish` clears both. A tap or a loop that is
//        replaced, never cancelled ahead, belongs in a `TransientRegistry<Task>` instead, where a
//        stale tombstone cannot cancel the next one.

import Foundation

/// PIN: a cancel that beats its register leaves a tombstone, because `.run` hands out no Task to cancel.
public final class RunRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [String: Task<Void, Never>] = [:]
    private var cancelled: Set<String> = []

    public init() {}

    @discardableResult
    /// Keeps `task` under `id`; false, and the caller cancels it, when a cancel came first.
    public func register(_ id: String, _ task: Task<Void, Never>) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if cancelled.contains(id) { return false }
        tasks[id] = task
        return true
    }

    /// Cancels the Task under `id`, or leaves a tombstone for one not registered yet.
    public func cancel(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        if let task = tasks[id] { task.cancel() }
        cancelled.insert(id)
    }

    /// Whether a cancel reached `id`.
    public func isCancelled(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled.contains(id)
    }

    /// Whether a Task is registered under `id`.
    public func isRunning(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return tasks[id] != nil
    }

    /// The run ended: its Task and its tombstone go.
    public func finish(_ id: String) {
        lock.lock(); tasks[id] = nil; cancelled.remove(id); lock.unlock()
    }
}
