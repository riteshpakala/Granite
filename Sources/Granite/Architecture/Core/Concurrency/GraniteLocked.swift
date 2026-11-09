//
//  GraniteLocked.swift
//  Granite
//
//  State that one thread at a time may touch.
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
#error("GraniteLocked has no lock primitive for this platform")
#endif

/// State behind a lock, in the shape of `Synchronization.Mutex`.
///
/// `Mutex` needs iOS 18 and macOS 15, and `OSAllocatedUnfairLock` macOS 13; the package's floor is
/// macOS 12, so Granite carries its own. One allocation holds both the state and the lock word.
///
/// This is the event layer's one `@unchecked Sendable` storage type. The invariant that makes it
/// sound: the state is reachable only inside ``withLock(_:)``, which holds the lock for the whole
/// of `body`, and `State` is `Sendable`, so whatever moves in or out of the lock may cross threads.
///
/// Never call out to unknown code (handlers, other locks) from inside `body`.
@usableFromInline
struct GraniteLocked<State: Sendable>: @unchecked Sendable {
    @usableFromInline let buffer: GraniteLockedBuffer<State>

    @usableFromInline
    init(_ initial: State) {
        buffer = GraniteLockedBuffer.make(initial)
    }

    @inlinable
    func withLock<Result>(_ body: (inout State) throws -> Result) rethrows -> Result {
        try buffer.withUnsafeMutablePointers { state, lock in
            GraniteLockedBuffer<State>.acquire(lock)
            defer { GraniteLockedBuffer<State>.release(lock) }
            return try body(&state.pointee)
        }
    }
}

/// The allocation behind ``GraniteLocked``: the state as the header, the lock word as the one
/// element, so the word's address is stable as the platform primitives require.
@usableFromInline
final class GraniteLockedBuffer<State>: ManagedBuffer<State, GranitePlatformLock> {

    static func make(_ initial: State) -> GraniteLockedBuffer<State> {
        let buffer = GraniteLockedBuffer<State>.create(minimumCapacity: 1) { _ in initial }
        let storage = unsafeDowncast(buffer, to: GraniteLockedBuffer<State>.self)
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
        // The header (the state) is destroyed by ManagedBuffer itself; the element is ours.
        withUnsafeMutablePointerToElements { pointer in
            #if !canImport(os)
            pthread_mutex_destroy(pointer)
            #endif
            _ = pointer.deinitialize(count: 1)
        }
    }

    @inlinable
    static func acquire(_ lock: UnsafeMutablePointer<GranitePlatformLock>) {
        #if canImport(os)
        os_unfair_lock_lock(lock)
        #else
        pthread_mutex_lock(lock)
        #endif
    }

    @inlinable
    static func release(_ lock: UnsafeMutablePointer<GranitePlatformLock>) {
        #if canImport(os)
        os_unfair_lock_unlock(lock)
        #else
        pthread_mutex_unlock(lock)
        #endif
    }
}
