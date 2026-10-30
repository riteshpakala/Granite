//  WHAT: The residents a Granite state cannot hold (actors, models, clients, sessions, Tasks), kept
//        by key; the state carries the key, a count or a revision, so a view still re-renders when
//        one changes.
//  PIN:  A LOCK, NOT AN ACTOR: a synchronous reducer and a main-thread helper read it in place. A
//        resident the next send needs is put by the helper before the send, never by a reducer.

import Foundation

public final class TransientRegistry<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Value] = [:]

    public init() {}

    public func put(_ key: String, _ value: Value) {
        lock.lock(); items[key] = value; lock.unlock()
    }

    public func get(_ key: String) -> Value? {
        lock.lock(); defer { lock.unlock() }
        return items[key]
    }

    /// The value under `key`, made by `make` (under the lock) when there is none: one per key,
    /// however many callers ask at once.
    public func value(_ key: String, make: () throws -> Value) rethrows -> Value {
        lock.lock(); defer { lock.unlock() }
        if let value = items[key] { return value }
        let made = try make()
        items[key] = made
        return made
    }

    @discardableResult
    public func remove(_ key: String) -> Value? {
        lock.lock(); defer { lock.unlock() }
        return items.removeValue(forKey: key)
    }

    public func contains(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return items[key] != nil
    }

    public func keys(prefix: String = "") -> [String] {
        lock.lock(); defer { lock.unlock() }
        return items.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }

    public func values() -> [Value] {
        lock.lock(); defer { lock.unlock() }
        return Array(items.values)
    }

    /// Removes and returns every value whose key starts with `prefix`.
    @discardableResult
    public func removeAll(prefix: String) -> [Value] {
        lock.lock(); defer { lock.unlock() }
        let gone = items.filter { $0.key.hasPrefix(prefix) }
        for key in gone.keys { items[key] = nil }
        return Array(gone.values)
    }

    public func removeAll() {
        lock.lock(); items.removeAll(); lock.unlock()
    }
}
