//
//  GraniteCustomEvent.swift
//  Granite
//
//  Created by Ritesh Pakala on 10/15/26.
//

import Foundation

/*
 A property wrapper declared OUTSIDE Granite that a center compiles beside its `@Event`s.

 `@Event` compiles into a `ReducerContainer` through `CompileableEvent`, which is internal:
 a wrapper another package declares is found by the center's reflection (it is an `AnyEvent`)
 but never compiled, so its sends go nowhere. This is the public half of that pass. Conform a
 wrapper to `GraniteCustomEvent` and `compile(with:)` runs when the hosting command compiles,
 with a host that reads the command's state, commits a new one and dispatches sibling reducers.
 The containers it returns are kept by the command and fired by reducer type, exactly as its
 own are (`GraniteEffect.chain`, `dispatch`). Lifecycle works unchanged: a wrapper whose
 `lifecycle` is `.onTask` has its `signal` sent when the component's task runs.

 Craft's `@Agent` — a reducer that runs an ML operation and streams frames into state — is
 the first such wrapper; Granite itself stays free of what the wrapper computes.
*/
public protocol GraniteCustomEvent: AnyEvent {
    /// Called once, when the hosting command compiles its events. The host is valid for the
    /// command's lifetime and a no-op after it.
    func compile(with host: GraniteEventHost) -> [any GraniteEventContainer]
}

/// What a compiled event keeps in its command: enough to be found by reducer type and fired.
public protocol GraniteEventContainer: AnyObject {
    var id: UUID { get }
    var label: String { get }
    /// The reducer type this container hosts, used to route ``GraniteEffect/chain(_:payload:)``.
    /// Nil for a container no reducer type names.
    var reducerType: AnyGraniteReducer.Type? { get }
    /// Fires this container with an optional payload.
    func fire(_ payload: GranitePayload?)
}

/// A compiled event's window onto its command: fresh state, a commit, sibling dispatch.
///
/// Holds the command weakly, as a `ReducerContainer` does. `@unchecked Sendable` for the same
/// reason as `GraniteEffect`: a wrapper hands it to the task that computes, and every call
/// lands on the command's own synchronisation.
public struct GraniteEventHost: @unchecked Sendable {
    weak var director: (any Director)?
    /// Whether the hosting command is an online service.
    public let isOnline: Bool

    init(director: any Director, isOnline: Bool) {
        self.director = director
        self.isOnline = isOnline
    }

    /// Whether the command is attached or appeared.
    public var isAvailable: Bool { director?.isAvailable ?? false }

    /// The command's state as it stands now; nil once the command is gone.
    public func state() -> AnyGraniteState? { director?.getState() }

    /// Replaces the command's state and persists it when its store auto-saves — one commit, as a
    /// reducer's.
    public func commit(_ state: AnyGraniteState) {
        director?.setState(state)
        director?.persistStateChanges()
    }

    /// Fires every sibling reducer of the given type in this command.
    public func dispatch(_ reducerType: AnyGraniteReducer.Type, payload: GranitePayload?) {
        director?.dispatch(reducerType, payload: payload)
    }

    /// Tells the command's `@Notify` listeners that a reducer of this type committed.
    public func notify(_ reducerType: AnyGraniteReducer.Type, payload: AnyGranitePayload?) {
        director?.notify(reducerType, payload: payload)
    }

    /// Compiles an ordinary reducer executable nested in a custom wrapper, as `@Event` would.
    public func compile<E: EventExecutable>(_ executable: E) -> [any GraniteEventContainer] {
        guard let director else { return [] }
        let container = ReducerContainer(executable, isOnline: isOnline)
        container.setup(director)
        return [container]
    }
}
