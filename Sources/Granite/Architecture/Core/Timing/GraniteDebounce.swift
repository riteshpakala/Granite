//
//  GraniteDebounce.swift
//  Granite
//
//  Debounce on Dispatch, with the same timing as Combine's `debounce`.
//

import Foundation
import Dispatch

/// Delivers a value once `interval` seconds pass with no newer one, on `queue`.
///
/// Owned by whoever receives through it. Scheduled work holds it weakly, so when the owner lets it
/// go a pending value is simply never delivered: nothing needs cancelling.
final class GraniteDebounce<Value: Sendable>: Sendable {
    private struct State: Sendable {
        var pending: Value?
        var generation: UInt64 = 0
    }

    private let interval: Double
    private let queue: DispatchQueue
    private let handler: @Sendable (Value) -> Void
    private let state = GraniteLocked(State())

    init(interval: Double, queue: DispatchQueue, handler: @escaping @Sendable (Value) -> Void) {
        self.interval = interval
        self.queue = queue
        self.handler = handler
    }

    func receive(_ value: Value) {
        let ticket = state.withLock { state -> UInt64 in
            state.pending = value
            state.generation &+= 1
            return state.generation
        }
        // An earlier value's work still runs, finds a newer ticket and does nothing.
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.fire(ticket)
        }
    }

    private func fire(_ ticket: UInt64) {
        let value = state.withLock { state -> Value? in
            guard state.generation == ticket, let value = state.pending else { return nil }
            state.pending = nil
            return value
        }
        if let value {
            handler(value)
        }
    }
}
