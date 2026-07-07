//
//  GraniteEffect.swift
//  Granite
//
//  Created by Granite architecture review.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation

/// A declarative description of follow-up work a reducer wants to run **after** it commits
/// its state change.
///
/// `GraniteEffect` is the type-safe, explicit alternative to reflection-based `@Event(.after)`
/// forwarding for *chaining reducers within a reducer*. Where `@Event(.after)` requires
/// declaring a nested `@Event` inside the reducer and relies on `Mirror` to discover and wire
/// it, an effect is an ordinary value you return from ``GraniteReducer/effect(state:payload:)``:
///
/// ```swift
/// struct Submit: GraniteReducer {
///     typealias Center = FormCenter
///
///     func reduce(state: inout Center.State) {
///         state.isSubmitting = true
///     }
///
///     // After Submit commits, run Validate, then kick off an async network call.
///     func effect(state: Center.State) -> GraniteEffect {
///         .merge(
///             .chain(Validate.self),
///             .run { await Analytics.track("submit") }
///         )
///     }
/// }
/// ```
///
/// The engine runs the returned effect on a deterministic schedule: for synchronous reducers
/// immediately after the state commit, and for `async` / `streamingTask` reducers strictly
/// after the awaited `reduce` completes. `.chain` targets any sibling reducer declared as an
/// `@Event` in the same ``GraniteCenter``; if no such reducer exists the chain is a safe no-op.
public struct GraniteEffect: @unchecked Sendable {

    enum Operation {
        case none
        case chain(AnyGraniteReducer.Type, GranitePayload?)
        case run(@Sendable () async -> Void)
        case merge([GraniteEffect])
    }

    let operation: Operation

    private init(_ operation: Operation) {
        self.operation = operation
    }

    /// No follow-up work. This is the default for reducers that don't override `effect`.
    public static var none: GraniteEffect { .init(.none) }

    /// Fires a sibling reducer declared as an `@Event` in the same center, optionally with a
    /// payload. Type-safe chaining without nested `@Event` reflection.
    public static func chain<R: GraniteReducer>(_ reducer: R.Type,
                                                payload: GranitePayload? = nil) -> GraniteEffect {
        .init(.chain(reducer, payload))
    }

    /// Runs arbitrary async work in a detached, cooperative `Task`. Use for fire-and-forget
    /// side effects (analytics, logging, prefetch). To feed results back into state, have the
    /// work call another reducer's `send` — prefer ``chain(_:payload:)`` when possible.
    public static func run(_ work: @Sendable @escaping () async -> Void) -> GraniteEffect {
        .init(.run(work))
    }

    /// Runs several effects in order.
    public static func merge(_ effects: [GraniteEffect]) -> GraniteEffect {
        .init(.merge(effects))
    }

    /// Runs several effects in order.
    public static func merge(_ effects: GraniteEffect...) -> GraniteEffect {
        .init(.merge(effects))
    }
}
