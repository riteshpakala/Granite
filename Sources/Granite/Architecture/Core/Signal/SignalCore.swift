//
//  SignalCore.swift
//  Granite
//
//  The shared storage behind a signal and all of its copies.
//

import Foundation

/// Subscribers and last value for one signal. Copies of a signal share one core.
///
/// The subscriber list is an immutable array swapped under the lock. `send` takes the lock
/// once to read it, then calls handlers with the lock released, so a handler may send, observe
/// or cancel on the same signal without deadlocking. Delivery is synchronous, on the sender's
/// thread.
@usableFromInline
final class SignalCore<Value>: @unchecked Sendable {
    let id = UUID()

    // `@usableFromInline` and `@inlinable send` let client modules specialize the delivery
    // loop for their concrete `Value`; unspecialized, generic copies dominate its cost.
    @usableFromInline let lock = GraniteLock()
    @usableFromInline var subscribers: ContiguousArray<SignalSubscription<Value>> = []
    @usableFromInline var latest: Value?
    /// How many subscribers want the previous value; `send` skips copying it when none do.
    @usableFromInline var changeObservers = 0

    init(lastValue: Value? = nil) {
        self.latest = lastValue
    }

    var lastValue: Value? {
        lock.withLock { latest }
    }

    var observerCount: Int {
        lock.withLock { subscribers.count }
    }

    /// Adds a handler for each sent value.
    func subscribe(_ handler: @escaping (Value) -> Void,
                           onCancel: (() -> Void)? = nil) -> SignalSubscription<Value> {
        add(SignalSubscription(core: self, handler: .value(handler), onCancel: onCancel))
    }

    /// Adds a handler for each sent value together with the value sent before it.
    func subscribeToChanges(_ handler: @escaping (Value, Value?) -> Void) -> SignalSubscription<Value> {
        add(SignalSubscription(core: self, handler: .change(handler), onCancel: nil))
    }

    @inlinable
    func send(_ value: Value) {
        lock.lock()
        let previous = changeObservers > 0 ? latest : nil
        latest = value
        let snapshot = subscribers
        lock.unlock()

        for subscription in snapshot {
            subscription.receive(value, previous: previous)
        }
    }

    private func add(_ subscription: SignalSubscription<Value>) -> SignalSubscription<Value> {
        lock.withLock {
            subscribers.append(subscription)
            if subscription.wantsPrevious { changeObservers += 1 }
        }
        return subscription
    }

    /// Cancels and removes every subscriber.
    func removeAll() {
        let removed = lock.withLock { () -> ContiguousArray<SignalSubscription<Value>> in
            let current = subscribers
            subscribers = []
            changeObservers = 0
            return current
        }
        for subscription in removed {
            subscription.cancel()
        }
    }

    fileprivate func remove(_ subscription: SignalSubscription<Value>) {
        lock.withLock {
            if let index = subscribers.firstIndex(where: { $0 === subscription }) {
                subscribers.remove(at: index)
                if subscription.wantsPrevious { changeObservers -= 1 }
            }
        }
    }
}

/// One handler on one signal. Cancelling it removes it from the signal and releases the
/// handler (and whatever the handler captured) straight away.
@usableFromInline
final class SignalSubscription<Value>: GraniteCancellable, @unchecked Sendable {
    @usableFromInline
    enum Handler {
        case value((Value) -> Void)
        case change((Value, Value?) -> Void)
    }

    fileprivate let wantsPrevious: Bool
    private weak var core: SignalCore<Value>?
    @usableFromInline var handler: Handler?
    private var onCancel: (() -> Void)?

    fileprivate init(core: SignalCore<Value>,
                     handler: Handler,
                     onCancel: (() -> Void)?) {
        if case .change = handler { wantsPrevious = true } else { wantsPrevious = false }
        self.core = core
        self.handler = handler
        self.onCancel = onCancel
        super.init()
    }

    @inlinable
    func receive(_ value: Value, previous: Value?) {
        // Checked per delivery: a handler cancelled by an earlier handler in the same fan-out
        // must not fire.
        let current = withStateLock { isCancelled in isCancelled ? nil : handler }
        switch current {
        case .value(let deliver): deliver(value)
        case .change(let deliver): deliver(value, previous)
        case nil: break
        }
    }

    override func didCancel() {
        let cleanup = withStateLock { _ -> (() -> Void)? in
            let action = onCancel
            handler = nil
            onCancel = nil
            return action
        }
        core?.remove(self)
        cleanup?()
    }
}
