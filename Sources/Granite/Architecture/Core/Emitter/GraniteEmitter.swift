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

    @usableFromInline let entries: GraniteLock<ContiguousArray<Entry>>

    public init() {
        entries = GraniteLock([])
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
        let removal = rewrite(appending: entry) { existing, _ in
            guard let key else { return false }
            return existing.key == key
        }
        Self.notify(removal.removed.filter { $0 !== receiver })
    }

    /// Removes `receiver`'s subscriptions: all of them, or only the one under `key`.
    public func off(_ receiver: AnyObject, key: GraniteEmitterKey? = nil) {
        _ = rewrite { existing, current in
            current === receiver && (key == nil || existing.key == key)
        }
    }

    /// How many subscriptions still have a live receiver.
    public var receiverCount: Int {
        // Counted from a snapshot, outside the lock: loading a weak reference can make this
        // thread the last owner of its object.
        let snapshot = entries.withLock { $0 }
        return snapshot.reduce(0) { $0 + ($1.receiver == nil ? 0 : 1) }
    }

    /// Removes every subscription, telling the receivers that can be told.
    func removeAll() {
        let removal = rewrite { _, _ in true }
        Self.notify(removal.removed)
    }

    /// Drops the subscriptions whose receivers are gone.
    @usableFromInline
    func compact() {
        _ = rewrite { _, _ in false }
    }

    /// What a change to the list took out of it, kept until the lock is released.
    ///
    /// Releasing an object runs its `deinit`, and whatever it owned alone goes with it: a
    /// handler's captures, a receiver's view. If any of that reached this emitter while its lock
    /// was held, the lock would be taken twice on one thread: a trap on Darwin, a deadlock
    /// elsewhere. So nothing is released under the lock. The entries taken out, and every
    /// receiver loaded to decide what to keep, are handed back and go when this does.
    private struct Removal {
        var entries: ContiguousArray<Entry> = []
        var loaded: [AnyObject & Sendable] = []
        /// The live receivers of the entries taken out.
        var removed: [AnyObject & Sendable] = []
    }

    /// Rebuilds the list under the lock: drops the entries whose receiver is gone and those
    /// `remove` picks, then appends `entry`. `remove` runs under the lock and must not call out.
    private func rewrite(appending entry: Entry? = nil,
                         remove: (Entry, AnyObject & Sendable) -> Bool) -> Removal {
        entries.withLock { list in
            var removal = Removal()
            var kept = ContiguousArray<Entry>()
            kept.reserveCapacity(list.count + 1)
            for existing in list {
                guard let receiver = existing.receiver else {
                    removal.entries.append(existing)
                    continue
                }
                removal.loaded.append(receiver)
                if remove(existing, receiver) {
                    removal.entries.append(existing)
                    removal.removed.append(receiver)
                } else {
                    kept.append(existing)
                }
            }
            if let entry {
                kept.append(entry)
            }
            // Every entry of the old list is now held by `kept` or `removal`, so replacing it
            // frees only its storage.
            list = kept
            return removal
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
