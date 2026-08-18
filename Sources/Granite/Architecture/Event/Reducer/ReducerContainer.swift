//
//  ReducerContainer.swift
//  Granite
//
//  Created by Ritesh Pakala on 07/21/22.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import SwiftUI

extension Storage {

    struct ReducerIdentifierKey : Hashable {
        let id : String
        let keyPath: AnyKeyPath
    }
    
}

protocol AnyReducerContainer {
    var id : UUID { get set }
    var label: String { get }
    /// The reducer type this container hosts, used to route ``GraniteEffect/chain(_:payload:)``.
    var reducerType: AnyGraniteReducer.Type? { get }
    func setup(_ coordinator: Director)
    /// Fires this container's reducer with an optional payload.
    func fire(_ payload: GranitePayload?)
}

//TODO: MAJOR
//When an @Event is inside a center it cannot be declared in a reducer
//Check @Event var sync: Sync.Reducer (May only be the case if the Relay/Service is in .online mode)
//infinite loop case as well
//
// 01/08/23 which is why we declare @Notify outside of reducers not within..................
//
// `@unchecked Sendable`: the container coordinates a reducer across its own serial queue
// and structured-concurrency `Task`s. Its mutable state is only touched from that serial
// queue / the reducer's task, so the unchecked conformance asserts that manual discipline.
final class ReducerContainer<Event : EventExecutable>: AnyReducerContainer, Prospectable, Nameable, @unchecked Sendable {
    public var id : UUID = .init()
    
    public var label: String {
        reducer?.label ?? ""
    }

    var reducerType: AnyGraniteReducer.Type? {
        reducer?.reducerType
    }

    func fire(_ payload: GranitePayload?) {
        if let payload {
            reducer?.send(payload)
        } else {
            reducer?.send()
        }
    }

    weak var coordinator: Director?
    
    var setState: ((AnyGraniteState) -> Void)?
    
    private let reducer: Event?
    var sideEffects: [Forwarding : [GraniteSignal.Payload<GranitePayload?>]] = [:]
    private let isTimed: Bool
    public let interval: Double
    private var timer: DisplayLinkTimer? = nil
    private var isOnline: Bool
    private var executionTask: Task<Void, Error>? = nil

    /// Gate for `GraniteReducerBehavior.persistentStreamingTask`: true while an
    /// execution owns the container. `NSLock` rather than the container's own
    /// `queue` — commits can arrive ON that queue (debounce/throttle schedule
    /// there), so a `queue.sync` gate would deadlock.
    private let persistentStreamLock = NSLock()
    private var isPersistentStreamRunning = false
    
    /// The container's single serial queue, created once in `init`. Reducer commits and
    /// `notify` fan-out are serialized here. (Previously a computed `thread` property
    /// allocated a fresh queue on every access, so `updateState` had no serialization
    /// guarantee at all.)
    public let queue: DispatchQueue

    var events: [AnyEvent] {
        reducer?.events ?? []
    }

    init(_ reducer: Event,
                isTimed: Bool = false,
                interval: Double = 0.0,
                isOnline: Bool = false) {
        self.reducer = reducer
        self.isTimed = isTimed
        self.interval = interval
        
        self.queue = .init(label: "granite.reducer.container.\(id.uuidString)", qos: .userInteractive)
        
        self.isOnline = isOnline
        self.reducer?.setOnline(isOnline)
        
        if isTimed {
            timer = .init()
        }
    }
    
    func setup(_ coordinator: Director) {
        self.coordinator = coordinator
        
        Prospector.shared.currentNode?.addChild(id: self.id, label: String(reflecting: Event.self), type: .event)
        Prospector.shared.push(id: self.id)
        bind()
        observe()
        Prospector.shared.pop()
    }
    
    func bind() {
        guard let reducer = self.reducer else {
            GraniteLog("🛥: No reducer", level: .error)
            return
        }
        
        reducer.signal.bind("signal")
        reducer.beamSignal.bind("beamSignal")
    }
    
    func observe() {
        guard let reducer = self.reducer else {
            GraniteLog("🛥: No reducer", level: .error)
            return
        }
        
        switch reducer.interaction {
        case .debounce(let interval):
            var signal = reducer.signal//TODO: revisit mutability + storage
            signal.debounce(interval: interval, scheduler: queue) += { [weak self] value in
                if let thread = reducer.thread {
                    thread.async { [weak self] in
                        self?.commit(value)
                    }
                } else {
                    self?.commit(value)
                }
            }
        case .throttle(let interval):
            var signal = reducer.signal//TODO: revisit mutability + storage
            signal.throttle(interval: interval, scheduler: queue) += { [weak self] value in
                if let thread = reducer.thread {
                    thread.async { [weak self] in
                        self?.commit(value)
                    }
                } else {
                    self?.commit(value)
                }
            }
        case .basic:
            reducer.signal += { [weak self] value in
                if let thread = reducer.thread {
                    thread.async { [weak self] in
                        self?.commit(value)
                    }
                } else {
                    self?.commit(value)
                }
            }
        }
        
        if reducer.isNotifiable {
            reducer.observe()
        }
    }
    
    func commit(_ value: GranitePayload?) {
        // A running `persistentStreamingTask` OWNS this container, so the send
        // is dropped WHOLE — decided before `update(value)`, which is what
        // keeps a dropped send from clobbering the payload the running
        // execution may still read.
        if case .persistentStreamingTask(let priority) = reducer?.behavior, isTimed == false {
            guard claimPersistentStream() else {
                GraniteLog("🛥: persistent stream already running, send dropped", level: .debug)
                return
            }

            reducer?.update(value)

            self.executionTask = Task(priority: priority) { [weak self] in
                // The gate reopens however this ends — return, throw, or
                // cancellation from somewhere other than `commit` — so a
                // stream can never strand the container busy forever.
                defer { self?.releasePersistentStream() }
                await self?.executeStreamingAsync()
            }
            return
        }

        reducer?.update(value)

        //TODO: this can support the updation of multiple instances of the same component
        //make sure not to allow this timer to run independently in each
        if self.isTimed == true {
            self.timer?.start { [weak self] instance in
                guard self?.coordinator?.isAvailable == true else {
                    instance.stop()
                    self?.timer = nil
                    return
                }

                self?.execute()
            }
        } else {
            switch reducer?.behavior {
            case .task(let priority):
                // A new send REPLACES the in-flight execution.
                self.executionTask?.cancel()
                self.executionTask = Task(priority: priority) { [weak self] in
                    await self?.executeAsync()
                }
            case .streamingTask(let priority):
                self.executionTask?.cancel()
                self.executionTask = Task(priority: priority) { [weak self] in
                    await self?.executeStreamingAsync()
                }
            default:
                // Synchronous reducers never assigned `executionTask`, so the
                // cancel that used to sit above this switch was always a
                // no-op here.
                self.execute()
            }
        }
    }

    /// Test-and-set in ONE acquisition: two sends can commit concurrently — a
    /// `.basic` interaction with no `thread` override commits on the sender's
    /// thread — so a read-then-write would let both claim the gate.
    private func claimPersistentStream() -> Bool {
        persistentStreamLock.lock()
        defer { persistentStreamLock.unlock() }
        guard isPersistentStreamRunning == false else { return false }
        isPersistentStreamRunning = true
        return true
    }

    private func releasePersistentStream() {
        persistentStreamLock.lock()
        isPersistentStreamRunning = false
        persistentStreamLock.unlock()
    }
    
    func execute() {
        
        //TODO: think about the necessity of before
        //it does not feel standard or correct to have
        //
        for signal in (sideEffects[.before] ?? []){
            signal.send(reducer?.payload as? GranitePayload)
        }
        
        //TODO: this CAN be a queue, before it hits an after

        if let newState = self.reducer?.execute(coordinator?.getState()) {
            updateState(newState)
            runEffect(for: newState)
        }

        for signal in (sideEffects[.after] ?? []){
            signal.send(reducer?.payload as? GranitePayload)
        }
    }

    func executeAsync() async {
        
        //TODO: think about the necessity of before
        //it does not feel standard or correct to have
        //
        for signal in (sideEffects[.before] ?? []){
            signal.send(reducer?.payload as? GranitePayload)
        }
        
        //TODO: this CAN be a queue, before it hits an after
        // a basic CS problem
        
        if let newState = await self.reducer?.executeAsync(coordinator?.getState()) {
            updateState(newState)
            runEffect(for: newState)
        }

        for signal in (sideEffects[.after] ?? []){
            signal.send(reducer?.payload as? GranitePayload)
        }
    }
    
    /// Runs a streaming async reducer. Instead of snapshotting state at entry and overwriting
    /// it at exit, the reducer receives a `stream` closure it calls after each mutation.
    /// Every `stream(state)` call is dispatched to the main thread so SwiftUI sees each
    /// incremental update immediately — no batching, no snapshot overwrite.
    func executeStreamingAsync() async {
        for signal in (sideEffects[.before] ?? []) {
            signal.send(reducer?.payload as? GranitePayload)
        }

        await self.reducer?.executeStreaming(coordinator?.getState()) { [weak self] newState in
            // Drop frames once the streaming task has been cancelled (e.g. a newer send
            // superseded this one) so a stale token no longer overwrites fresher state.
            guard Task.isCancelled == false else { return }
            DispatchQueue.main.async {
                self?.updateState(newState)
            }
        }

        // Effects run after the whole stream completes, against the latest state.
        if let latest = coordinator?.getState() {
            runEffect(for: latest)
        }

        for signal in (sideEffects[.after] ?? []) {
            signal.send(reducer?.payload as? GranitePayload)
        }
    }

    /// Resolves and runs the ``GraniteEffect`` a reducer declares for its committed state.
    /// This is the explicit, type-safe chaining path that complements `.before`/`.after`
    /// signal forwarding. Effects always run *after* the state commit.
    private func runEffect(for state: AnyGraniteState) {
        guard let effect = reducer?.resolveEffect(state) else { return }
        run(effect)
    }

    private func run(_ effect: GraniteEffect) {
        switch effect.operation {
        case .none:
            break
        case .chain(let reducerType, let payload):
            coordinator?.dispatch(reducerType, payload: payload)
        case .run(let work):
            Task { await work() }
        case .merge(let effects):
            for effect in effects { run(effect) }
        }
    }

    func updateState(_ newState: AnyGraniteState) {
        self.coordinator?.setState(newState)

        self.queue.async { [weak self] in
            guard let self else { return }
            if let reducerType = self.reducer?.reducerType {
                self.coordinator?.notify(reducerType,
                                         payload: self.reducer?.payload)
            }
        }
    }
}
