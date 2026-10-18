//
//  GraniteSignal.swift
//  Granite
//
//  A value-less event: `send()` notifies every observer.
//

import Foundation

/// What every signal offers the rest of Granite.
protocol AnyGraniteSignal: Inspectable {
    var observerCount: Int { get }
    func removeAllObservers()
}

extension AnyGraniteSignal {
    /// Prepares a signal for a fresh owner, by default dropping its existing observers.
    func bind(_ name: String? = nil, removeObservers: Bool = true) {
        guard removeObservers else { return }
        removeAllObservers()
        didRemoveObservers()
    }
}

/// A value-less event. Copies share one set of observers.
///
/// Observing stores the subscription in ``Prospector/current`` (or the scope you pass), so it
/// ends with that scope. The returned token can also be cancelled directly, and dropping it
/// does not end the subscription.
public struct GraniteSignal: AnyGraniteSignal {
    @usableFromInline let core: SignalCore<Void>

    public var id: UUID { core.id }

    public init() {
        self.core = SignalCore()
    }

    @inlinable
    public func send() {
        core.send(())
    }

    /// Observes in the scope bound to the current task or thread.
    @discardableResult
    public func observe(handler: @escaping () -> Void) -> GraniteCancellable {
        observe(in: Prospector.current, handler: handler)
    }

    /// Observes in `scope`. With `nil`, the subscription lasts until cancelled or until the
    /// signal is released.
    @discardableResult
    public func observe(in scope: Prospect?, handler: @escaping () -> Void) -> GraniteCancellable {
        let subscription = core.subscribe { _ in handler() }
        scope?.store(subscription)
        return subscription
    }

    public var observerCount: Int { core.observerCount }

    func removeAllObservers() {
        core.removeAll()
    }

    public func didRemoveObservers() {}

    @discardableResult
    public static func += (lhs: GraniteSignal, rhs: @escaping () -> Void) -> GraniteCancellable {
        lhs.observe(handler: rhs)
    }
}
