//
//  GraniteEmitter.swift
//  Granite
//
//  An event source whose subscriptions last exactly as long as whoever receives them.
//

import Foundation

/// Names one subscription on an emitter: subscribing again under the same key replaces it.
public struct GraniteEmitterKey: Hashable, Sendable {
    let name: String

    public init(_ name: String) {
        self.name = name
    }
}

/// A receiver an emitter tells when it drops it to make room: another subscription took its key,
/// or the emitter was cleared for a new owner. Lets an owner release what the receiver holds at
/// once instead of when the receiver itself goes.
protocol GraniteEmitterDisplaceable: AnyObject, Sendable {
    func displaced()
}

/// Sends values to receivers, synchronously and in subscription order.
///
/// **No tokens.** ``on(_:key:_:)`` holds the receiver *weakly* and hands it back to the handler
/// on each send, so the handler need not capture it. The subscription ends when the receiver is
/// released; there is nothing to store, cancel or tear down in a `deinit`. ``off(_:key:)`` exists
/// for early removal and is never needed for correctness.
///
/// **Delivery** runs on the sender's thread. The lock is held only to read the subscriber list, so
/// a handler may send, subscribe or unsubscribe on the same emitter. A receiver released by an
/// earlier handler in the same send is not reached; ``off(_:key:)`` and replacing a key take
/// effect from the next send.
///
/// **Concurrency.** `Sendable` and checked: values and handlers are `Sendable`, and the subscriber
/// list lives behind one lock.
public final class GraniteEmitter<Value: Sendable>: Sendable {
    // One subscription. A class, so a send reads each weak reference where it lives: copying a
    // weak reference out of a struct costs more than the delivery itself.
    #if compiler(>=6.2)
    @usableFromInline
    final class Entry: Sendable {
        @usableFromInline weak let receiver: (AnyObject & Sendable)?
        @usableFromInline let key: GraniteEmitterKey?
        @usableFromInline let deliver: @Sendable (AnyObject, Value) -> Void

        init(receiver: AnyObject & Sendable,
             key: GraniteEmitterKey?,
             deliver: @escaping @Sendable (AnyObject, Value) -> Void) {
            self.receiver = receiver
            self.key = key
            self.deliver = deliver
        }
    }
    #else
    // Before Swift 6.2 a weak reference cannot be `let`. `receiver` is written once, in `init`,
    // and only loaded after; a weak load is safe against its object's deallocation on any thread.
    @usableFromInline
    final class Entry: @unchecked Sendable {
        @usableFromInline weak var receiver: (AnyObject & Sendable)?
        @usableFromInline let key: GraniteEmitterKey?
        @usableFromInline let deliver: @Sendable (AnyObject, Value) -> Void

        init(receiver: AnyObject & Sendable,
             key: GraniteEmitterKey?,
             deliver: @escaping @Sendable (AnyObject, Value) -> Void) {
            self.receiver = receiver
            self.key = key
            self.deliver = deliver
        }
    }
    #endif

    @usableFromInline let entries: GraniteLocked<ContiguousArray<Entry>>

    public init() {
        entries = GraniteLocked([])
    }

    /// Sends `value` to every live receiver, in subscription order, on this thread.
    @inlinable
    public func send(_ value: Value) {
        let snapshot = entries.withLock { $0 }
        var released = false
        for entry in snapshot {
            // Loaded now, not when the snapshot was taken, so a receiver released earlier in this
            // same send is not reached.
            guard let receiver = entry.receiver else {
                released = true
                continue
            }
            entry.deliver(receiver, value)
        }
        if released {
            compact()
        }
    }

    /// Subscribes `receiver`, held weakly, until it is released.
    ///
    /// With a `key`, any subscription already under that key is removed first and this one is
    /// added last, whoever its receiver was.
    ///
    /// Reach what the handler needs through the receiver it is handed rather than capturing it:
    /// the handler itself is let go when a later send or subscribe finds its receiver gone.
    public func on<Receiver: AnyObject & Sendable>(_ receiver: Receiver,
                                                   key: GraniteEmitterKey? = nil,
                                                   _ handler: @escaping @Sendable (Receiver, Value) -> Void) {
        let entry = Entry(receiver: receiver, key: key) { object, value in
            // Every entry is made here with its own receiver, so the object handed back is that
            // receiver.
            handler(unsafeDowncast(object, to: Receiver.self), value)
        }
        let displaced = entries.withLock { list -> [AnyObject & Sendable] in
            var displaced: [AnyObject & Sendable] = []
            list.removeAll { existing in
                guard let current = existing.receiver else { return true }
                guard let key, existing.key == key else { return false }
                if current !== receiver {
                    displaced.append(current)
                }
                return true
            }
            list.append(entry)
            return displaced
        }
        Self.notify(displaced)
    }

    /// Removes `receiver`'s subscriptions: all of them, or only the one under `key`.
    public func off(_ receiver: AnyObject, key: GraniteEmitterKey? = nil) {
        entries.withLock { list in
            list.removeAll { existing in
                guard let current = existing.receiver else { return true }
                return current === receiver && (key == nil || existing.key == key)
            }
        }
    }

    /// How many subscriptions still have a live receiver.
    public var receiverCount: Int {
        entries.withLock { list in
            list.reduce(0) { $0 + ($1.receiver == nil ? 0 : 1) }
        }
    }

    /// Removes every subscription, telling the receivers that can be told.
    func removeAll() {
        let removed = entries.withLock { list -> [AnyObject & Sendable] in
            let live = list.compactMap(\.receiver)
            list.removeAll()
            return live
        }
        Self.notify(removed)
    }

    /// Drops the subscriptions whose receivers are gone.
    @usableFromInline
    func compact() {
        entries.withLock { list in
            list.removeAll { $0.receiver == nil }
        }
    }

    private static func notify(_ displaced: [AnyObject & Sendable]) {
        for receiver in displaced {
            (receiver as? GraniteEmitterDisplaceable)?.displaced()
        }
    }
}

extension GraniteEmitter where Value == Void {
    @inlinable
    public func send() {
        send(())
    }
}
