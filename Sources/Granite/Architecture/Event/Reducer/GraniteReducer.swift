//
//  GraniteReducer.swift
//  Granite
//
//  Created by Ritesh Pakala on 8/8/20.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation
import SwiftUI
import CoreData

extension Storage {
    struct ExpeditionIdentifierKey : Hashable {
        let id : String
        let keyPath: AnyKeyPath
    }
    
    struct EventSignalIdentifierKey : Hashable {
        let id : UUID
        let keyPath : AnyKeyPath
    }
    
}

public protocol AnyGraniteReducer: Findable {
    var notifiable: Bool { get }
}

//TODO: This is not friendly for stored Events in Components that have multiple instances
//For each instance shares the observer child that is to a singular signal for example
//when one deinits, all the other signals will not observe
//or, only the latest will
//these need to somehow be copied and removed per instance rather
//then using the storage to pull the same one based on this protocol description
//
//08/2023 the above may have been resolved with recent sync changes?
extension AnyGraniteReducer {
    public var id : UUID {
        if let id = Storage.shared.value(at: Storage.ExpeditionIdentifierKey(id: String(describing: self), keyPath: \Self.self)) as? UUID {
            return id
        }
        else {
            let id = UUID()
            Storage.shared.setValue(id, at: Storage.ExpeditionIdentifierKey(id: String(describing: self), keyPath: \Self.self))
            return id
        }
    }
    
    public var idSync : UUID {
        if let id = Storage.shared.value(at: Storage.ExpeditionIdentifierKey(id: "\(Self.self)" /*String(describing: self)*/, keyPath: \Self.idSync)) as? UUID {
            return id
        }
        else {
            let id = UUID()
            Storage.shared.setValue(id, at: Storage.ExpeditionIdentifierKey(id: "\(Self.self)"/*String(describing: self)*/, keyPath: \Self.idSync))
            return id
        }
    }
    
    /// Where `@Notify` nudges this reducer. The executable hosting it re-sends what arrives.
    var notifyEmitter : GraniteEmitter<GranitePayload> {
        Storage.shared.value(at: Storage.EventSignalIdentifierKey(id: self.id, keyPath: \AnyGraniteReducer.notifyEmitter)) {
            GraniteEmitter<GranitePayload>()
        }
    }

    /// Shared by every instance of this reducer type: what a reducer sends here reaches every
    /// `listen(.broadcast(…))` on any of them. Listeners are held weakly, by whoever listens.
    public var broadcast : GraniteEmitter<GranitePayload?> {
        Storage.shared.value(at: Storage.EventSignalIdentifierKey(id: self.idSync, keyPath: \AnyGraniteReducer.broadcast)) {
            GraniteEmitter<GranitePayload?>()
        }
    }

    /// Kept for source compatibility. Sending from the reducer value itself has never reached a
    /// container; send through the executable (`center.reducer.send()`) instead.
    public func send() {}

    /// Kept for source compatibility. Sending from the reducer value itself has never reached a
    /// container; send through the executable (`center.reducer.send(_:)`) instead.
    public func send(_ payload: GranitePayload) {}
    
    public var notifiable: Bool {
        false
    }
}

public enum GraniteReducerBehavior {
    case task(TaskPriority)
    /// Like `task` but skips the final `updateState` after the reducer returns.
    /// Use this for streaming reducers that push state mid-flight via internal `send` calls.
    /// The initial state snapshot is passed in for reading, but the coordinator's state
    /// is never overwritten by the snapshot once the reducer finishes.
    case streamingTask(TaskPriority)
    /// Streaming execution that a re-send may NOT cancel.
    /// (a voice session, a device watcher, a subscription).
    case persistentStreamingTask(TaskPriority)
    case none

    var isTask: Bool {
        switch self {
        case .task, .streamingTask, .persistentStreamingTask:
            return true
        default:
            return false
        }
    }

    var priority: TaskPriority? {
        switch self {
        case .task(let p), .streamingTask(let p), .persistentStreamingTask(let p):
            return p
        default:
            return nil
        }
    }
}

public enum GraniteReducerInteraction {
    case debounce(Double)
    case throttle(Double)
    case basic
}

/// A unit of logic that mutates a center's state.
///
/// Implement one of the `reduce(state:)` overloads to mutate `inout` state synchronously,
/// asynchronously (with `behavior` set to `.task`), or as a stream (`.streamingTask`). Declare
/// follow-up work — including chaining sibling reducers — by returning a ``GraniteEffect`` from
/// ``effect(state:)``. See <doc:ReducersAndEvents>.
public protocol GraniteReducer: AnyGraniteReducer {
    typealias Reducer = GraniteReducerExecutable<Self>

    associatedtype Center: GraniteCenter
    associatedtype Metadata: GranitePayload = EmptyGranitePayload
    
    func reduce(state: inout Center.GenericGraniteState)
    func reduce(state: inout Center.GenericGraniteState) async
    func reduce(state: inout Center.GenericGraniteState, payload: Metadata)
    func reduce(state: inout Center.GenericGraniteState, payload: Metadata) async
    /// Called by `streamingTask` reducers. `stream` pushes mid-flight state to the
    /// coordinator on the main thread so every mutation is immediately visible to SwiftUI.
    func reduce(state: inout Center.GenericGraniteState,
                stream: @escaping (Center.GenericGraniteState) -> Void) async

    /// Declares follow-up work to run after this reducer commits, as a ``GraniteEffect``.
    /// Return `.none` (the default) for no side effects. Override this to chain sibling
    /// reducers (`.chain`) or run async work (`.run`) in a type-safe way instead of via
    /// reflection-based `@Event(.after)` forwarding.
    func effect(state: Center.GenericGraniteState) -> GraniteEffect

    /// Payload-aware variant of ``effect(state:)``. Defaults to calling ``effect(state:)``.
    func effect(state: Center.GenericGraniteState, payload: Metadata) -> GraniteEffect

    var thread: DispatchQueue? { get }
    var behavior: GraniteReducerBehavior { get }

    init()
}

extension GraniteReducer {
    public var thread: DispatchQueue? {
        nil
    }
    
    public var behavior: GraniteReducerBehavior {
        .none
    }
    
    /// The instanced version of ``AnyGraniteReducer/broadcast``: what a reducer sends here reaches
    /// the one `listen(.beam)` made last.
    public var beam : GraniteEmitter<GranitePayload?> {
        Storage.shared.value(at: "\(String(describing: self))_beam") {
            GraniteEmitter<GranitePayload?>()
        }
    }
}

extension GraniteReducer {
    public func reduce(state: inout Center.GenericGraniteState) {}
    public func reduce(state: inout Center.GenericGraniteState) async {}
    public func reduce(state: inout Center.GenericGraniteState, payload: Metadata) {}
    public func reduce(state: inout Center.GenericGraniteState, payload: Metadata) async {}
    public func reduce(state: inout Center.GenericGraniteState,
                       stream: @escaping (Center.GenericGraniteState) -> Void) async {}

    public func effect(state: Center.GenericGraniteState) -> GraniteEffect { .none }
    public func effect(state: Center.GenericGraniteState, payload: Metadata) -> GraniteEffect {
        effect(state: state)
    }
}

public protocol EventExecutable {
    var label : String { get }
    var reducerType : AnyGraniteReducer.Type { get }
    /// What `send` sends on: the reducer's container receives it, and so do
    /// `listen(.bubble(…))` handlers.
    var emitter : GraniteEmitter<GranitePayload?> { get }
    /// The reducer's `beam`, which its container clears when it takes the reducer.
    var beamEmitter: GraniteEmitter<GranitePayload?> { get }
    /// Where `@Notify` nudges the reducer; its container re-sends what arrives.
    var notifyEmitter: GraniteEmitter<GranitePayload> { get }

    var payload: AnyGranitePayload? { get set }
    var events: [AnyEvent] { get }
    var isNotifiable: Bool { get }
    var behavior: GraniteReducerBehavior { get }
    var interaction: GraniteReducerInteraction { get }

    var thread: DispatchQueue? { get }

    func setOnline(_ isOnline: Bool)

    func send()
    func send(_ payload: GranitePayload)

    /// Runs `handler` on the main actor for each payload the reducer sends to `kind`.
    ///
    /// Inside a component's `listeners`, the handler lasts while the component is on screen.
    /// Elsewhere it lasts as long as this reducer, or until a later `listen` takes its place.
    @discardableResult
    func listen(_ kind: GraniteReducerListenKind, _ handler: @escaping @MainActor @Sendable (GranitePayload?) -> Void ) -> Self
    
    func update(_ payload: GranitePayload?)
    func execute(_ state: AnyGraniteState?) -> AnyGraniteState
    func executeAsync(_ state: AnyGraniteState?) async -> AnyGraniteState
    /// Resolves the ``GraniteEffect`` this reducer declares for the given committed state.
    func resolveEffect(_ state: AnyGraniteState?) -> GraniteEffect
    func executeStreaming(_ state: AnyGraniteState?,
                         stream: @escaping (AnyGraniteState) -> Void) async
    init()
    init(debounce interval: Double)
    init(throttle interval: Double)
}

public enum GraniteReducerListenKind {
    case broadcast(String = "granite.reducer.listener.broadcast")
    case beam
    case bubble(String = "granite.reducer.listener.bubble")
}

open class GraniteReducerExecutable<Expedition: GraniteReducer>: EventExecutable {
    private lazy var expedition: Expedition = {
        .init()
    }()
    
    public let id: UUID = .init()
    
    public var label: String {
        "\(Expedition.self)"
    }
    
    public var reducerType: AnyGraniteReducer.Type {
        Expedition.self
    }
    
    private var isOnline: Bool = false

    /// What ``send()`` and ``send(_:)`` send on. Its container receives first, then any
    /// `listen(.bubble(…))` handlers.
    public let emitter = GraniteEmitter<GranitePayload?>()

    public var thread: DispatchQueue? {
        expedition.thread
    }

    public var beamEmitter: GraniteEmitter<GranitePayload?> {
        expedition.beam
    }

    public var notifyEmitter: GraniteEmitter<GranitePayload> {
        expedition.notifyEmitter
    }

    /// Handlers registered by `listen` outside any `listeners` body, such as from a view's
    /// `.task`. They last as long as this reducer, or until a later `listen` takes their place.
    let ownListeners = GraniteListeners()

    private var payloadFindAttempted: Bool = false
    public var payload : AnyGranitePayload?

    /// Memoized reflection. A reducer's `@Event` children are fixed for its lifetime, so we
    /// reflect over `expedition` exactly once instead of on every access — the previous
    /// behavior, which the engine's own notes flagged as a cause of slow component boot
    /// (each `events` read walked the Mirror tree again, recursively for nested events).
    private var cachedEvents: [AnyEvent]? = nil
    public var events : [AnyEvent] {
        if let cachedEvents { return cachedEvents }
        let found = expedition.findEvents()
        cachedEvents = found
        return found
    }
    public var isNotifiable : Bool {
        expedition.notifiable
    }
    
    public var behavior: GraniteReducerBehavior {
        expedition.behavior
    }
    
    public var interaction: GraniteReducerInteraction

    required public init() {
        self.interaction = .basic
        //self.payload = expedition.findPayload()
    }
    
    required public init(debounce interval: Double) {
        self.interaction = .debounce(interval)
        //self.payload = expedition.findPayload()
    }
    
    required public init(throttle interval: Double) {
        self.interaction = .throttle(interval)
        //self.payload = expedition.findPayload()
    }
    
    public func execute(_ state: AnyGraniteState?) -> AnyGraniteState {
        var mutableState = (state as? Expedition.Center.GenericGraniteState) ?? Expedition.Center.GenericGraniteState()
        
        find()
        
        if let payload = self.payload as? Expedition.Metadata {
            expedition.reduce(state: &mutableState, payload: payload)
        } else {
            expedition.reduce(state: &mutableState)
        }
        
        return mutableState
    }
    
    public func executeAsync(_ state: AnyGraniteState?) async -> AnyGraniteState {
        var mutableState = (state as? Expedition.Center.GenericGraniteState) ?? Expedition.Center.GenericGraniteState()
        
        find()
        
        if let payload = payload as? Expedition.Metadata {
            await expedition.reduce(state: &mutableState, payload: payload)
        } else {
            await expedition.reduce(state: &mutableState)
        }
        
        return mutableState
    }
    
    public func executeStreaming(_ state: AnyGraniteState?,
                                 stream: @escaping (AnyGraniteState) -> Void) async {
        var mutableState = (state as? Expedition.Center.GenericGraniteState) ?? Expedition.Center.GenericGraniteState()

        find()

        await expedition.reduce(state: &mutableState, stream: { stream($0) })
    }

    public func resolveEffect(_ state: AnyGraniteState?) -> GraniteEffect {
        guard let typedState = state as? Expedition.Center.GenericGraniteState else { return .none }
        find()
        if let payload = self.payload as? Expedition.Metadata {
            return expedition.effect(state: typedState, payload: payload)
        } else {
            return expedition.effect(state: typedState)
        }
    }

    public func setOnline(_ isOnline: Bool) {
        self.isOnline = isOnline
    }
    
    private func find() {
        guard payloadFindAttempted == false else { return }
        if self.payload == nil {
            self.payload = expedition.findPayload()
            self.payloadFindAttempted = true
        }
    }
    
    public func update(_ payload: GranitePayload?) {
        find()

        if self.payload == nil || self.payload is GranitePayload {
            // Direct Metadata payloads are values, so each send must replace the previous
            // value. Calling their default `update` implementation is intentionally a no-op.
            self.payload = payload
        } else {
            // A reflected @Payload wrapper owns stable storage and updates its container.
            self.payload?.update(payload)
        }
    }
    
    @discardableResult
    public func listen(_ kind: GraniteReducerListenKind, _ handler: @escaping @MainActor @Sendable (GranitePayload?) -> Void ) -> Self {
        let binding = GraniteListeners.bound
        let listeners: GraniteListeners
        if binding.isBound {
            // Called from a `listeners` body whose owner has since gone (for instance from a task
            // the body started): there is no one left to deliver to.
            guard let bound = binding.set else { return self }
            listeners = bound
        } else {
            listeners = ownListeners
        }

        switch kind {
        case .beam:
            // `beam` is keyed by `String(describing: reducer)`, so it is effectively shared by
            // type; clearing it keeps "last listener wins" across instances.
            expedition.beam.removeAll()
            listeners.register(.init(executable: id, kind: .beam, name: ""),
                               on: expedition.beam,
                               handler: handler)
        case .broadcast(let name):
            listeners.register(.init(executable: id, kind: .broadcast, name: name),
                               on: expedition.broadcast,
                               handler: handler)
        case .bubble(let name):
            listeners.register(.init(executable: id, kind: .bubble, name: name),
                               on: emitter,
                               handler: handler)
        }
        return self
    }
    @discardableResult
    public func listen(_ handler: @escaping @MainActor @Sendable (GranitePayload?) -> Void ) -> Self {
        self.listen(.beam, handler)
    }

    public func send() {
        if self.payload is GranitePayload {
            self.payload = nil
        } else {
            self.payload?.clear()
        }
        emitter.send(nil)
    }

    public func send(_ payload: GranitePayload) {
        update(payload)
        emitter.send(payload)
    }
    
    public func attach(_ payload: GranitePayload) {
        update(payload)
    }
}
