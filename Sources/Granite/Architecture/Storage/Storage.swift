//
//  Storage.swift
//  Granite
//
//  Created by Ritesh Pakala on 08/11/22.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation

/// A process-wide, lock-guarded key/value registry used by the reducer engine to
/// memoize signals and identifiers.
///
/// `Storage` intentionally stores heterogeneous `Any` values, so it opts out of the
/// compiler's automatic `Sendable` checking and guarantees thread-safety manually via
/// an internal lock. Every accessor takes the lock, so concurrent reads and writes from
/// reducer queues and the main thread are safe.
//TODO: swap out for GraniteCache
final class Storage: @unchecked Sendable {

    static let shared = Storage()

    private let lock = NSRecursiveLock()
    private var values = [AnyHashable : Any]()

    /// Returns the value stored at `key`, allocating (and caching) a new one via
    /// `allocator` when absent. The allocation happens under the lock so two threads
    /// racing on the same key observe a single shared value.
    func value<T>(at key : AnyHashable, allocator : () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        if let value = values[key] as? T {
            return value
        }
        else {
            let value = allocator()
            values[key] = value
            return value
        }
    }

    func value(at key : AnyHashable) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func setValue<T>(_ value : T, at key : AnyHashable) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func hasValue(at key : AnyHashable) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return values[key] != nil
    }

    func removeValue(at key : AnyHashable) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = nil
    }

}
