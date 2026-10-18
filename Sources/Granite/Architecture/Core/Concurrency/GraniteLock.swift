//
//  GraniteLock.swift
//  Granite
//
//  A non-recursive mutex that builds on Darwin and Linux alike.
//

#if canImport(os)
import os
@usableFromInline typealias GranitePlatformLock = os_unfair_lock_s
#elseif canImport(Glibc)
import Glibc
@usableFromInline typealias GranitePlatformLock = pthread_mutex_t
#elseif canImport(Musl)
import Musl
@usableFromInline typealias GranitePlatformLock = pthread_mutex_t
#else
#error("GraniteLock has no lock primitive for this platform")
#endif

/// A small non-recursive mutex: `os_unfair_lock` on Darwin, `pthread_mutex_t` elsewhere.
///
/// A value wrapper over one heap object whose tail allocation holds the lock word, so the
/// word's address is stable as the primitives require and each lock costs one allocation.
/// `Synchronization.Mutex` can replace this once the package's floor reaches iOS 18 / macOS 15.
///
/// Never call out to unknown code (handlers, other locks) while holding it.
@usableFromInline
struct GraniteLock: @unchecked Sendable {
    @usableFromInline let storage: GraniteLockStorage

    init() {
        storage = GraniteLockStorage.make()
    }

    @inlinable
    func lock() {
        storage.lock()
    }

    @inlinable
    func unlock() {
        storage.unlock()
    }

    @inlinable
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        storage.lock()
        defer { storage.unlock() }
        return try body()
    }
}

// `@usableFromInline` so lock and unlock inline (and specialize) into client modules: the
// send path crosses the module boundary on every delivery.
@usableFromInline
final class GraniteLockStorage: ManagedBuffer<Void, GranitePlatformLock> {

    static func make() -> GraniteLockStorage {
        let buffer = GraniteLockStorage.create(minimumCapacity: 1) { _ in () }
        let storage = unsafeDowncast(buffer, to: GraniteLockStorage.self)
        storage.withUnsafeMutablePointerToElements { pointer in
            #if canImport(os)
            pointer.initialize(to: os_unfair_lock_s())
            #else
            pointer.initialize(to: pthread_mutex_t())
            let status = pthread_mutex_init(pointer, nil)
            precondition(status == 0, "pthread_mutex_init failed: \(status)")
            #endif
        }
        return storage
    }

    deinit {
        withUnsafeMutablePointerToElements { pointer in
            #if !canImport(os)
            pthread_mutex_destroy(pointer)
            #endif
            _ = pointer.deinitialize(count: 1)
        }
    }

    @inlinable
    func lock() {
        withUnsafeMutablePointerToElements { pointer in
            #if canImport(os)
            os_unfair_lock_lock(pointer)
            #else
            pthread_mutex_lock(pointer)
            #endif
        }
    }

    @inlinable
    func unlock() {
        withUnsafeMutablePointerToElements { pointer in
            #if canImport(os)
            os_unfair_lock_unlock(pointer)
            #else
            pthread_mutex_unlock(pointer)
            #endif
        }
    }
}
