//  WHAT: A service's live instance, resolved when it is needed instead of stored.
//  PIN:  STORED RELAYS POINT DOWN, NEVER BACK. Building a relay builds its service's reducers, and
//        building a reducer builds its stored relays; Granite stores the relay only after that. A
//        reducer with a stored `@Relay` to its own service, or two services whose reducers relay to
//        each other, recurse at construction: signal 11 (verified on Granite c67f491). A reducer
//        reaches its own service with `Live.service(Self.self)` from its effect, which runs on main
//        after construction.

import Foundation
import Granite

public enum Live {
    nonisolated(unsafe) private static var cache: [ObjectIdentifier: Any] = [:]
    private static let lock = NSLock()

    /// Call on the main thread: a `thread: .main` reducer's `effect`, a view, a root.
    public static func service<S: GraniteService>(_ type: S.Type = S.self) -> S {
        let key = ObjectIdentifier(type)
        lock.lock()
        if let cached = cache[key] as? S { lock.unlock(); return cached }
        lock.unlock()
        let resolved = MainActor.assumeIsolated { Resolved(Relay<S>().wrappedValue) }.service
        lock.lock(); cache[key] = resolved; lock.unlock()
        return resolved
    }

    /// Carries a service out of `MainActor.assumeIsolated`, which returns only what is `Sendable`. The
    /// service is read on main, as every relay is.
    private struct Resolved<S>: @unchecked Sendable {
        let service: S
        init(_ service: S) { self.service = service }
    }
}
