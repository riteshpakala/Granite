//
//  GraniteBubble+Route.swift
//  Granite
//
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation

/// A route offered inside `onBubble(_:)`: what runs when a view below sends
/// an action with this route's key.
///
/// A key is an optional ``GraniteBubble/Name`` plus the exact type of the value sent.
/// Closures are routed with `On`; reducers are routed with
/// ``GraniteReducerExecutable/on(_:)``:
///
/// ```swift
/// HeaderView()
///     .onBubble {
///         center.vote.on(.upvote) { (post: Post) in Vote.Meta(post, .up) }
///         On(.goToThread) { showThread() }
///         On { (community: Community) in open(community) }
///     }
/// ```
public struct On {
    let name: GraniteBubble.Name?
    let type: Any.Type
    let body: any GraniteBubbleRouteBody

    init(name: GraniteBubble.Name?, type: Any.Type, body: any GraniteBubbleRouteBody) {
        self.name = name
        self.type = type
        self.body = body
    }

    /// Routes a value by its type alone.
    public init<Value>(_ type: Value.Type = Value.self, perform: @escaping (Value) -> Void) {
        self.init(name: nil, type: Value.self, body: ValueRoute(perform: perform))
    }

    /// Routes a value sent under `name`.
    public init<Value>(_ name: GraniteBubble.Name,
                       _ type: Value.Type = Value.self,
                       perform: @escaping (Value) -> Void) {
        self.init(name: name, type: Value.self, body: ValueRoute(perform: perform))
    }

    /// Routes a named action that sends no value.
    public init(_ name: GraniteBubble.Name, perform: @escaping () -> Void) {
        self.init(name: name, type: Void.self, body: ActionRoute(perform: perform))
    }

    struct Key: Hashable {
        let name: GraniteBubble.Name?
        let type: ObjectIdentifier
    }

    var key: Key {
        Key(name: name, type: ObjectIdentifier(type))
    }

    var label: String {
        "(\(name.map { ".\($0.rawValue)" } ?? "unnamed"), \(type))"
    }
}

/// What a route does with a value whose key matched.
///
/// Every conformer is at most three words (a closure, a reducer, or a reducer and a closure),
/// so it sits in the existential's inline buffer: a route never boxes its body.
protocol GraniteBubbleRouteBody {
    @MainActor
    func deliver<Value>(_ value: Value)
}

struct ValueRoute<Payload>: GraniteBubbleRouteBody {
    let perform: (Payload) -> Void

    func deliver<Value>(_ value: Value) {
        guard let payload = value as? Payload else { return }
        perform(payload)
    }
}

struct ActionRoute: GraniteBubbleRouteBody {
    let perform: () -> Void

    func deliver<Value>(_ value: Value) {
        perform()
    }
}

// MARK: Reducers

extension GraniteReducerExecutable {
    /// Routes the reducer's own payload, sent as is.
    ///
    /// ```swift
    /// center.viewCommunity.on()     // a view sends ViewCommunity.Meta
    /// ```
    ///
    /// A reducer without a payload is reached by name instead, with ``on(_:)``; routed
    /// unnamed, no view could reach it, which traps in debug builds.
    public func on() -> On {
        On(name: nil, type: bubbledType(Expedition.self), body: SendRoute(reducer: self))
    }

    /// Routes the reducer's own payload sent under `name`, or, for a reducer without a
    /// payload, the bare `name`.
    ///
    /// ```swift
    /// center.refresh.on(.refresh)   // a view sends .refresh
    /// ```
    public func on(_ name: GraniteBubble.Name) -> On {
        On(name: name, type: bubbledType(Expedition.self), body: SendRoute(reducer: self))
    }

    /// Routes a value of any type, mapped into the reducer's payload before it is sent.
    /// Several reducers can take the same input under different names.
    ///
    /// ```swift
    /// center.upvote.on(.upvote) { (post: Post) in Vote.Meta(post: post, direction: .up) }
    /// center.bookmark.on(.bookmark) { (post: Post) in Bookmark.Meta(post: post) }
    /// ```
    public func on<Input>(_ name: GraniteBubble.Name? = nil,
                          map: @escaping (Input) -> Expedition.Metadata) -> On {
        On(name: name, type: Input.self, body: MapRoute(reducer: self, map: map))
    }

    /// Routes a bare `name`, building the reducer's payload where the route is installed,
    /// from the installer's own state.
    ///
    /// ```swift
    /// center.vote.on(.upvote) { Vote.Meta(post: post, direction: .up) }
    /// ```
    public func on(_ name: GraniteBubble.Name,
                   map: @escaping () -> Expedition.Metadata) -> On {
        On(name: name, type: Void.self, body: MakeRoute(reducer: self, make: map))
    }

    /// Routes the reducer's own payload, running `perform` with it before it is sent.
    ///
    /// ```swift
    /// center.reply.on(.reply) { (meta: Reply.Meta) in dismissSheet() }
    /// ```
    public func on(_ name: GraniteBubble.Name? = nil,
                   perform: @escaping (Expedition.Metadata) -> Void) -> On {
        On(name: name, type: Expedition.Metadata.self, body: EffectRoute(reducer: self, perform: perform))
    }

    /// Routes like ``on(_:)``, running `perform` before the reducer is sent.
    ///
    /// ```swift
    /// center.edit.on(.edit) { GraniteHaptic.light.invoke() }
    /// ```
    public func on(_ name: GraniteBubble.Name? = nil,
                   perform: @escaping () -> Void) -> On {
        On(name: name, type: bubbledType(Expedition.self), body: EffectActionRoute(reducer: self, perform: perform))
    }
}

/// The type a view sends to reach a reducer: its payload, or nothing when it takes none.
private func bubbledType<Expedition: GraniteReducer>(_ expedition: Expedition.Type) -> Any.Type {
    takesPayload(expedition) ? Expedition.Metadata.self : Void.self
}

private func takesPayload<Expedition: GraniteReducer>(_ expedition: Expedition.Type) -> Bool {
    Expedition.Metadata.self != EmptyGranitePayload.self
}

/// Sends the bubbled value to the reducer when it takes one, and a bare send when it doesn't.
private func send<Expedition: GraniteReducer, Value>(_ reducer: GraniteReducerExecutable<Expedition>,
                                                     _ value: Value) {
    if takesPayload(Expedition.self), let payload = value as? Expedition.Metadata {
        reducer.send(payload)
    } else {
        reducer.send()
    }
}

struct SendRoute<Expedition: GraniteReducer>: GraniteBubbleRouteBody {
    let reducer: GraniteReducerExecutable<Expedition>

    func deliver<Value>(_ value: Value) {
        send(reducer, value)
    }
}

struct MapRoute<Input, Expedition: GraniteReducer>: GraniteBubbleRouteBody {
    let reducer: GraniteReducerExecutable<Expedition>
    let map: (Input) -> Expedition.Metadata

    func deliver<Value>(_ value: Value) {
        guard let input = value as? Input else { return }
        send(reducer, map(input))
    }
}

struct MakeRoute<Expedition: GraniteReducer>: GraniteBubbleRouteBody {
    let reducer: GraniteReducerExecutable<Expedition>
    let make: () -> Expedition.Metadata

    func deliver<Value>(_ value: Value) {
        send(reducer, make())
    }
}

struct EffectRoute<Expedition: GraniteReducer>: GraniteBubbleRouteBody {
    let reducer: GraniteReducerExecutable<Expedition>
    let perform: (Expedition.Metadata) -> Void

    func deliver<Value>(_ value: Value) {
        guard let payload = value as? Expedition.Metadata else { return }
        perform(payload)
        send(reducer, payload)
    }
}

struct EffectActionRoute<Expedition: GraniteReducer>: GraniteBubbleRouteBody {
    let reducer: GraniteReducerExecutable<Expedition>
    let perform: () -> Void

    func deliver<Value>(_ value: Value) {
        perform()
        send(reducer, value)
    }
}
