//
//  SignalDelivery.swift
//  Granite
//
//  Debounce and throttle on Dispatch, replacing the Combine operators.
//

import Foundation
import Dispatch

/// How a signal copy delivers values to the handlers observed through it.
enum SignalDelivery: Sendable {
    case immediate
    case debounce(interval: Double, queue: DispatchQueue)
    case throttle(interval: Double, queue: DispatchQueue, latest: Bool)
}

extension SignalDelivery {
    /// Builds the per-subscription forwarder. Each observation gets its own timing state, as
    /// each subscription to a Combine debounce or throttle does.
    func wrap<Value>(_ handler: @escaping (Value) -> Void)
        -> (forward: (Value) -> Void, cancel: (() -> Void)?) {
        switch self {
        case .immediate:
            return (handler, nil)
        case .debounce(let interval, let queue):
            let debouncer = Debouncer(interval: interval, queue: queue, handler: handler)
            return ({ debouncer.receive($0) }, { debouncer.cancel() })
        case .throttle(let interval, let queue, let latest):
            let throttler = Throttler(interval: interval, queue: queue, latest: latest, handler: handler)
            return ({ throttler.receive($0) }, { throttler.cancel() })
        }
    }
}

/// Delivers a value once `interval` seconds pass with no newer value, on `queue`.
final class Debouncer<Value>: @unchecked Sendable {
    private let lock = GraniteLock()
    private let interval: Double
    private let queue: DispatchQueue
    private var handler: ((Value) -> Void)?
    private var pending: Value?
    private var generation: UInt64 = 0
    private var workItem: DispatchWorkItem?

    init(interval: Double, queue: DispatchQueue, handler: @escaping (Value) -> Void) {
        self.interval = interval
        self.queue = queue
        self.handler = handler
    }

    func receive(_ value: Value) {
        lock.lock()
        guard handler != nil else {
            lock.unlock()
            return
        }
        pending = value
        generation &+= 1
        let ticket = generation
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.fire(ticket) }
        workItem = item
        lock.unlock()

        queue.asyncAfter(deadline: .now() + interval, execute: item)
    }

    func cancel() {
        lock.lock()
        handler = nil
        pending = nil
        let item = workItem
        workItem = nil
        lock.unlock()
        item?.cancel()
    }

    private func fire(_ ticket: UInt64) {
        lock.lock()
        guard ticket == generation, let handler, let value = pending else {
            lock.unlock()
            return
        }
        pending = nil
        workItem = nil
        lock.unlock()

        handler(value)
    }
}

/// Delivers at most one value per `interval` seconds, on `queue`.
///
/// Matches Combine's `throttle(for:scheduler:latest:)`: the first value after a quiet period
/// is scheduled at once, and values arriving within the interval are coalesced into one
/// delivery at the interval's end — the newest when `latest` is true, else the first.
final class Throttler<Value>: @unchecked Sendable {
    private let lock = GraniteLock()
    private let interval: Double
    private let queue: DispatchQueue
    private let latest: Bool
    private var handler: ((Value) -> Void)?
    private var pending: Value?
    private var hasPending = false
    private var isScheduled = false
    private var lastEmission: DispatchTime?

    init(interval: Double, queue: DispatchQueue, latest: Bool, handler: @escaping (Value) -> Void) {
        self.interval = interval
        self.queue = queue
        self.latest = latest
        self.handler = handler
    }

    func receive(_ value: Value) {
        lock.lock()
        guard handler != nil else {
            lock.unlock()
            return
        }
        if latest || hasPending == false {
            pending = value
            hasPending = true
        }
        guard isScheduled == false else {
            lock.unlock()
            return
        }
        isScheduled = true

        let now = DispatchTime.now()
        var due: DispatchTime?
        if let lastEmission {
            let next = lastEmission + interval
            if next > now { due = next }
        }
        lock.unlock()

        if let due {
            queue.asyncAfter(deadline: due) { [weak self] in self?.emit() }
        } else {
            queue.async { [weak self] in self?.emit() }
        }
    }

    func cancel() {
        lock.withLock {
            handler = nil
            pending = nil
            hasPending = false
        }
    }

    private func emit() {
        lock.lock()
        isScheduled = false
        guard let handler, hasPending, let value = pending else {
            lock.unlock()
            return
        }
        pending = nil
        hasPending = false
        lastEmission = .now()
        lock.unlock()

        handler(value)
    }
}
