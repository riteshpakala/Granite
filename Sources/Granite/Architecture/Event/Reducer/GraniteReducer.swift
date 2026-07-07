//
//  GraniteReducer.swift
//  Granite
//
//  Created by Ritesh Pakala on 8/8/20.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
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
    
    public var valueSignal : GraniteSignal.Payload<GranitePayload?> {
        Storage.shared.value(at: Storage.EventSignalIdentifierKey(id: self.id, keyPath: \AnyGraniteReducer.valueSignal)) {
            GraniteSignal.Payload<GranitePayload?>()
        }
    }
    
    public var nudgeNotifyGraniteSignal : GraniteSignal.Payload<GranitePayload> {
        Storage.shared.value(at: Storage.EventSignalIdentifierKey(id: self.id, keyPath: \AnyGraniteReducer.nudgeNotifyGraniteSignal)) {
            GraniteSignal.Payload<GranitePayload>()
        }
    }
    
    //shared (signals ui receivers)
    public var broadcast : GraniteSignal.Payload<GranitePayload?> {
        Storage.shared.value(at: Storage.EventSignalIdentifierKey(id: self.idSync, keyPath: \AnyGraniteReducer.broadcast)) {
            GraniteSignal.Payload<GranitePayload?>()
        }
    }
    
    public func send() {
        valueSignal.send(nil)
    }
    
    public func send(_ payload: GranitePayload) {
        valueSignal.send(payload)
    }
    
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
    case none

    var isTask: Bool {
        switch self {
        case .task, .streamingTask:
            return true
        default:
            return false
        }
    }

    var priority: TaskPriority? {
        switch self {
        case .task(let p), .streamingTask(let p):
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
    
    //instanced version of broadcast
    public var beam : GraniteSignal.Payload<GranitePayload?> {
        Storage.shared.value(at: "\(String(describing: self))_beam") {
            GraniteSignal.Payload<GranitePayload?>()
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
    var signal : GraniteSignal.Payload<GranitePayload?> { get }
    var intermediateSignal : GraniteSignal.Payload<GranitePayload?> { get }
    var beamSignal: GraniteSignal.Payload<GranitePayload?> { get }
    
    var payload: AnyGranitePayload? { get set }
    var events: [AnyEvent] { get }
    var isNotifiable: Bool { get }
    var behavior: GraniteReducerBehavior { get }
    var interaction: GraniteReducerInteraction { get }
    
    var thread: DispatchQueue? { get }
    
    func setOnline(_ isOnline: Bool)
    
    func observe()
    
    func send()
    func send(_ payload: GranitePayload)
    
    @discardableResult
    func listen(_ kind: GraniteReducerListenKind, _ handler: @escaping (GranitePayload?) -> Void ) -> Self
    
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
    
    public var signal : GraniteSignal.Payload<GranitePayload?> {
        valueSignal
    }
    
    public var thread: DispatchQueue? {
        expedition.thread
    }
    
    public var valueSignal : GraniteSignal.Payload<GranitePayload?> = .init()
     
    public var intermediateSignal : GraniteSignal.Payload<GranitePayload?> = .init()
    
    public var beamSignal: GraniteSignal.Payload<GranitePayload?> {
        expedition.beam
    }
    
    public var synchronousGraniteSignalValue : GraniteSignal.Payload<GranitePayload?> {
        expedition.valueSignal
    }
    
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
    
    //instanced signals (Receiver)
    internal var beamCancellables: Set<AnyCancellable> = .init()
    //shared signals (Receiver)
    internal var broadcastCancellables: [String : AnyCancellable] = [:]
    //component tree (Receiver)
    internal var bubbledCancellables: [String : AnyCancellable] = [:]
    
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
    
    deinit {
        // Cancel only THIS instance's subscriptions. We deliberately do NOT call
        // `expedition.beam.removeObservers()` / `expedition.broadcast.removeObservers()`
        // here: `beam` and `broadcast` are type-shared signals (keyed by reducer type in
        // `Storage`), so `removeObservers()` would wipe the shared Prospector node holding
        // EVERY live instance's observers — tearing down sibling components' subscriptions.
        // Cancelling the per-instance cancellables removes exactly this instance's observer.
        beamCancellables.forEach { $0.cancel() }
        beamCancellables.removeAll()
        broadcastCancellables.values.forEach { $0.cancel() }
        broadcastCancellables = [:]
        bubbledCancellables.values.forEach { $0.cancel() }
        bubbledCancellables = [:]
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
        //TODO: make sure it is okay that a nil check is not required
        //Otherwise in notify requests and repetitive subsequent ones
        //the last payload persists
        if self.payload == nil {
            //Covers typealias alternative
            self.payload = payload
        }
        //Covers property wrapper case
        self.payload?.update(payload)
    }
    
    public func observe() {
        expedition.nudgeNotifyGraniteSignal += { [weak self] value in
            self?.send(value)
        }
    }
    
    @discardableResult
    public func listen(_ kind: GraniteReducerListenKind, _ handler: @escaping (GranitePayload?) -> Void ) -> Self {
        switch kind {
        case .beam:
            beamCancellables.forEach { $0.cancel() }
            beamCancellables.removeAll()
            expedition.beam.removeObservers()
            beamCancellables.insert(expedition.beam += handler)
        case .broadcast(let id):
            broadcastCancellables[id]?.cancel()
            broadcastCancellables[id] = (expedition.broadcast += handler)
        case .bubble(let id):
            bubbledCancellables[id]?.cancel()
            bubbledCancellables[id] = signal += handler
        }
        return self
    }
    @discardableResult
    public func listen(_ handler: @escaping (GranitePayload?) -> Void ) -> Self {
        self.listen(.beam, handler)
    }
    
    public func send() {
        self.payload?.clear()
        signal.send(nil)
    }
    
    public func send(_ payload: GranitePayload) {
        update(payload)
        signal.send(payload)
    }
    
    public func attach(_ payload: GranitePayload) {
        update(payload)
    }
}
