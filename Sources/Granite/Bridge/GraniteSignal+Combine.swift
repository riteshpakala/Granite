//
//  GraniteSignal+Combine.swift
//  Granite
//
//  Combine interop for Granite's signals, on platforms that have Combine. Kept out of
//  Architecture/Core so that folder never depends on Combine.
//

#if canImport(Combine)
import Combine
import Foundation

// `cancel()` already matches, so tokens drop into `Set<AnyCancellable>` via `store(in:)`.
extension GraniteCancellable: Cancellable {}

extension AnyCancellable {
    /// Hands a Combine subscription to a Granite scope, which cancels it when the scope ends.
    public func store(in prospect: Prospect) {
        prospect.store(GraniteCancellable { self.cancel() })
    }
}

extension GraniteSignal {
    /// The signal as a Combine publisher. Each subscriber is an ordinary observer of the signal.
    public var publisher: AnyPublisher<Void, Never> {
        GraniteSignalPublisher(core: core, delivery: .immediate).eraseToAnyPublisher()
    }
}

extension GraniteSignal.Payload {
    /// The signal as a Combine publisher, honouring this copy's debounce or throttle.
    public var publisher: AnyPublisher<Value, Never> {
        GraniteSignalPublisher(core: core, delivery: delivery).eraseToAnyPublisher()
    }
}

/// Publishes a signal's values. Honours demand, and drops values sent while a subscriber has
/// no outstanding demand, as `PassthroughSubject` does.
struct GraniteSignalPublisher<Output>: Publisher {
    typealias Failure = Never

    let core: SignalCore<Output>
    let delivery: SignalDelivery

    func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Never {
        let subscription = GraniteSignalSubscription(subscriber: subscriber)
        subscriber.receive(subscription: subscription)
        subscription.start(core: core, delivery: delivery)
    }
}

private final class GraniteSignalSubscription<Target: Subscriber>: Subscription, @unchecked Sendable
    where Target.Failure == Never {

    let combineIdentifier = CombineIdentifier()

    private let lock = GraniteLock()
    private var subscriber: Target?
    private var demand: Subscribers.Demand = .none
    private var token: GraniteCancellable?

    init(subscriber: Target) {
        self.subscriber = subscriber
    }

    func start(core: SignalCore<Target.Input>, delivery: SignalDelivery) {
        let (forward, cancelTiming) = delivery.wrap { [weak self] (value: Target.Input) in
            self?.deliver(value)
        }
        let subscription = core.subscribe(forward, onCancel: cancelTiming)

        let alreadyCancelled = lock.withLock { () -> Bool in
            guard subscriber != nil else { return true }
            token = subscription
            return false
        }
        if alreadyCancelled {
            subscription.cancel()
        }
    }

    func request(_ additional: Subscribers.Demand) {
        lock.withLock { demand += additional }
    }

    func cancel() {
        let current = lock.withLock { () -> GraniteCancellable? in
            subscriber = nil
            let current = token
            token = nil
            return current
        }
        current?.cancel()
    }

    private func deliver(_ value: Target.Input) {
        let target = lock.withLock { () -> Target? in
            guard let subscriber, demand > .none else { return nil }
            demand -= 1
            return subscriber
        }
        guard let target else { return }

        let more = target.receive(value)
        if more > .none {
            lock.withLock { demand += more }
        }
    }
}
#endif
