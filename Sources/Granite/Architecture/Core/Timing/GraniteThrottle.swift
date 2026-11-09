//
//  GraniteThrottle.swift
//  Granite
//
//  Throttle on Dispatch, with the same timing as Combine's `throttle(for:scheduler:latest:)`.
//

import Foundation
import Dispatch

/// Delivers at most one value per `interval` seconds, on `queue`.
///
/// The first value after a quiet period is scheduled at once; values arriving within the interval
/// are coalesced into one delivery at its end: the newest when `latest` is true, else the first.
///
/// Owned by whoever receives through it. Scheduled work holds it weakly, so when the owner lets it
/// go a pending value is simply never delivered: nothing needs cancelling.
final class GraniteThrottle<Value: Sendable>: Sendable {
    private struct State: Sendable {
        var pending: Value?
        var hasPending = false
        var isScheduled = false
        var lastEmission: DispatchTime?
    }

    private enum Schedule {
        case none
        case now
        case at(DispatchTime)
    }

    private let interval: Double
    private let queue: DispatchQueue
    private let latest: Bool
    private let handler: @Sendable (Value) -> Void
    private let state = GraniteLock(State())

    init(interval: Double, queue: DispatchQueue, latest: Bool = true, handler: @escaping @Sendable (Value) -> Void) {
        self.interval = interval
        self.queue = queue
        self.latest = latest
        self.handler = handler
    }

    func receive(_ value: Value) {
        let latest = self.latest
        let interval = self.interval
        // A value it replaces is released after the lock, never under it.
        let (schedule, replaced) = state.withLock { state -> (Schedule, Value?) in
            var replaced: Value? = nil
            if latest || state.hasPending == false {
                replaced = state.pending
                state.pending = value
                state.hasPending = true
            }
            guard state.isScheduled == false else { return (.none, replaced) }
            state.isScheduled = true

            if let lastEmission = state.lastEmission {
                let next = lastEmission + interval
                if next > .now() { return (.at(next), replaced) }
            }
            return (.now, replaced)
        }
        withExtendedLifetime(replaced) {}

        switch schedule {
        case .none:
            break
        case .now:
            queue.async { [weak self] in self?.emit() }
        case .at(let due):
            queue.asyncAfter(deadline: due) { [weak self] in self?.emit() }
        }
    }

    private func emit() {
        let value = state.withLock { state -> Value? in
            state.isScheduled = false
            guard state.hasPending, let value = state.pending else { return nil }
            state.pending = nil
            state.hasPending = false
            state.lastEmission = .now()
            return value
        }
        if let value {
            handler(value)
        }
    }
}
