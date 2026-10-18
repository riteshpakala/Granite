//
//  GraniteSignal.Payload.swift
//  Granite
//
//  An event that carries a value.
//

import Foundation
import Dispatch

extension GraniteSignal {
    /// An event carrying a value. Copies share one set of observers and one last value.
    ///
    /// ``debounced(_:on:)`` and ``throttled(_:on:latest:)`` return a copy whose *observers*
    /// receive values through that timing; sending is unaffected and reaches every observer.
    public struct Payload<Value>: AnyGraniteSignal {
        @usableFromInline let core: SignalCore<Value>
        private(set) var delivery: SignalDelivery = .immediate

        public var id: UUID { core.id }

        /// The most recently sent value, or `initial` before the first send.
        public var lastValue: Value? { core.lastValue }

        public init(_ initial: Value? = nil) {
            self.core = SignalCore(lastValue: initial)
        }

        @inlinable
        public func send(_ value: Value) {
            core.send(value)
        }

        // MARK: Observing

        /// Observes in the scope bound to the current task or thread.
        @discardableResult
        public func observe(handler: @escaping (Value) -> Void) -> GraniteCancellable {
            observe(in: Prospector.current, handler: handler)
        }

        /// Observes in `scope`. With `nil`, the subscription lasts until cancelled or until the
        /// signal is released.
        @discardableResult
        public func observe(in scope: Prospect?, handler: @escaping (Value) -> Void) -> GraniteCancellable {
            let (forward, cancelTiming) = delivery.wrap(handler)
            let subscription = core.subscribe(forward, onCancel: cancelTiming)
            scope?.store(subscription)
            return subscription
        }

        /// Observes each send together with the value sent before it. The first send after an
        /// unseeded init has no previous value and is skipped. Always immediate.
        @discardableResult
        public func observeChange(handler: @escaping (_ new: Value, _ previous: Value) -> Void) -> GraniteCancellable {
            let subscription = core.subscribeToChanges { value, previous in
                guard let previous else { return }
                handler(value, previous)
            }
            Prospector.current?.store(subscription)
            return subscription
        }

        // MARK: Delivery

        /// A copy whose observers receive a value once `interval` seconds pass without a newer
        /// one, on `queue`.
        public func debounced(_ interval: Double, on queue: DispatchQueue) -> Self {
            var copy = self
            copy.delivery = .debounce(interval: interval, queue: queue)
            return copy
        }

        /// A copy whose observers receive at most one value per `interval` seconds, on `queue`
        /// — the newest of each window when `latest` is true, else the first.
        public func throttled(_ interval: Double, on queue: DispatchQueue, latest: Bool = true) -> Self {
            var copy = self
            copy.delivery = .throttle(interval: interval, queue: queue, latest: latest)
            return copy
        }

        @available(*, deprecated, renamed: "debounced(_:on:)")
        public mutating func debounce(interval: Double, scheduler: DispatchQueue) -> Self {
            self = debounced(interval, on: scheduler)
            return self
        }

        @available(*, deprecated, renamed: "throttled(_:on:latest:)")
        public mutating func throttle(interval: Double, scheduler: DispatchQueue) -> Self {
            self = throttled(interval, on: scheduler, latest: true)
            return self
        }

        // MARK: Inspection

        public var observerCount: Int { core.observerCount }

        func removeAllObservers() {
            core.removeAll()
        }

        public func didRemoveObservers() {}

        @discardableResult
        public static func += (lhs: Self, rhs: @escaping (Value) -> Void) -> GraniteCancellable {
            lhs.observe(handler: rhs)
        }
    }
}
