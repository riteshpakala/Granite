//
//  GraniteMain.swift
//  Granite
//
//  The one way the event layer reaches the main actor.
//

import Foundation
import Dispatch

/// Runs work on the main actor: at once when the caller is already on the main thread, otherwise
/// on the main queue's next turn.
///
/// Inline on main keeps today's ordering for main-thread senders: a listener runs before the send
/// that reached it returns. From any other thread the work is queued on `DispatchQueue.main`, the
/// same serial queue streaming reducers commit through, so deliveries from one thread arrive in
/// the order they were sent.
enum GraniteMain {
    static func run(_ body: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            // On the main thread the main actor's executor is the current one, so this check
            // holds; it traps rather than races if that is ever not true.
            MainActor.assumeIsolated(body)
        } else {
            DispatchQueue.main.async { body() }
        }
    }
}
