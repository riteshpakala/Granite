//
//  GraniteCommand.swift
//  Granite
//
//  Created by Ritesh Pakala on 12/12/21.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation
import Combine

extension Storage {
    
    struct CommandIdentifierKey : Hashable {
        let id : String
        let keyPath: AnyKeyPath
    }
    
}

public enum GraniteCommandKind: CustomStringConvertible {
    
    case service(GraniteRelayKind)
    case component
    
    var isOnline: Bool {
        switch self {
        case .service(let kind):
            return kind == .online
        default:
            return false
        }
    }
    
    public var description: String {
        switch self {
        case .service(let relayKind):
            return "🛸\(relayKind == .online ? "[🛰]" : "")"
        case .component:
            return "📡"
        }
    }
}

/*
 A GraniteComponent's and GraniteService's Core event router,
 state manager, and responder.
*/
public class GraniteCommand<Center: GraniteCenter>: Inspectable, Findable, Director, Nameable, ObservableObject {
    public enum BuildBehavior {
        case dependency(AnyGranitePayload?)
        case none
    }
    
    /// One serial queue per command, created once. The previous computed property
    /// allocated a brand-new `DispatchQueue` on *every* access, which meant work
    /// dispatched "onto the command's queue" actually landed on a different queue each
    /// time — giving zero serialization guarantee and churning transient queues.
    let thread: DispatchQueue

    internal var cancellables = Set<AnyCancellable>()
    public let id: UUID

    /// This command's scope. Its reducers' subscriptions and its listener sets live under it,
    /// and all of them end when the command does. A component's command is re-parented under
    /// its enclosing component's scope through the SwiftUI environment.
    public let prospect: Prospect

    /// One child scope per `listen` key, replaced on each `listen` and ended by
    /// `removeListeners`. Guarded because hosts may drive appear/disappear off the main thread.
    private let listenerLock = GraniteLock()
    private var listenerScopes: [UUID: Prospect] = [:]
    
    public var isOnline: Bool {
        if case .service(.online) = kind {
            return true 
        } else {
            return false
        }
    }
    
    public var isLoaded: Bool {
        center.findStore()?.isLoaded == true
    }
    
    public internal(set) var center: Center
    
    var lifecycle: GraniteLifecycle = .none
    
    var onAppear: [GraniteSignal.Payload<GranitePayload?>]?
    var onDisappear: [GraniteSignal.Payload<GranitePayload?>]?
    var onTask: [GraniteSignal.Payload<GranitePayload?>]?
    var events: [AnyEvent]?
    var didAppear: (() -> Void)?
    var didDisappear: (() -> Void)?
    var runTasks: (() -> Void)?
    
    //@Event public var discoveryDiagnostic: DiagnoseTree<Center>.Reducer
    internal var reducers: [any GraniteEventContainer] = []
    internal var notifies: [String: AnyNotify] = [:]
    
    internal var listenersSet: Bool = false
    
    fileprivate var kind: GraniteCommandKind
    public var buildBehavior: BuildBehavior
    
    init(_ kind: GraniteCommandKind, initialCenter: Center? = nil) {
        let id: UUID = .init()
        self.id = id
        self.thread = DispatchQueue(label: "granite.command.\(id.uuidString)", qos: .userInitiated)
        self.kind = kind
        self.buildBehavior = .none

        // Parented to whatever scope is bound while this command is built: a relay for a
        // service's command, a parent command for a nested service, none for a component
        // built lazily by `@StateObject` (the environment attaches it later).
        let prospect = Prospect(id: id, label: String(reflecting: Self.self), type: .command)
        self.prospect = prospect
        center = prospect.withScope { initialCenter ?? Center() }
        prospect.withScope { setup() }
    }
    
    deinit {
        lifecycle = .deLink
        prospect.cancel()
    }
    
    func build(_ buildBehavior: BuildBehavior) {
        self.buildBehavior = buildBehavior
    }
    
    func setup() {
        switch kind {
        case .component:
            guard let store = center.findStore() else { return }
            store.restore()
        default:
            break
        }
        
        bind()
        observe()
    }
    
    func bind() {
        guard let store = center.findStore() else {
            return
        }
        
        /*
         TODO: MAJOR
         Compile()'s contents is the culprit to slow component
         build times.
         
         This is due to the recursive nature of Event findind in
         @Event nesting
         
         Update: 08/2023
         the change was done a while ago, but preloading service states
         `async` solved slow responsiveness.
         */
        compile()
        
        store.willChange.bind("stateWillChange")
    }
    
    /// Runs `listeners` in a fresh child scope keyed by `id`, so every signal it observes
    /// ends with ``removeListeners(_:)``. Listening again under the same key replaces the
    /// previous set instead of stacking a duplicate.
    public func listen(_ id: UUID? = nil, _ listeners: () -> Void) {
        listenersSet = true

        let key = id ?? self.id
        let scope = prospect.child(label: "listeners", type: .listeners)
        let previous = listenerLock.withLock { () -> Prospect? in
            let previous = listenerScopes[key]
            listenerScopes[key] = scope
            return previous
        }
        previous?.cancel()

        scope.withScope(listeners)
        GraniteLog("applying listeners to: \(NAME)", level: .debug)
    }
    
    public func removeListeners(_ id: UUID? = nil) {
        let key = id ?? self.id
        let scope = listenerLock.withLock { listenerScopes.removeValue(forKey: key) }
        scope?.cancel()
    }
    
    func observe() {
        guard let store = center.findStore() else { return }
        
        /*
         We want to update the UI with state changes
         Services have relays to handle updates onto the UI
         this, would be redundant
         
         lifecycle observers don't affect services
         */
        
        guard case .component = kind else { return }
        
        store
            .container
            .objectWillChange
            // DispatchQueue.main, not RunLoop.main: the RunLoop scheduler only fires in
            // the default run-loop mode, so state → UI delivery froze for as long as a
            // finger was down (touch tracking runs the loop in UITrackingRunLoopMode).
            // The throttle already delivers on the main queue, so the sink runs on main —
            // no redundant re-dispatch needed, and [weak self] avoids a crash if the
            // command deallocates while a throttled tick is in flight.
            .throttle(for: .seconds(0.0167), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }.store(in: &cancellables)
        
        //Observed here, signal sent by Component+View
        didAppear = { [weak self] in
            // Non-blocking: the previous `thread.sync` synchronously blocked the main
            // thread (didAppear is invoked from SwiftUI's .onAppear) on a background queue,
            // risking priority inversion. Fire the onAppear events asynchronously instead.
            self?.thread.async { [weak self] in
                self?.onAppear?.forEach { event in
                    switch self?.buildBehavior {
                    case .dependency(let payload):
                        event.send(payload as? GranitePayload)
                    default:
                        event.send(nil)
                    }
                }
            }

            self?.lifecycle = .appeared
        }
        
        didDisappear = { [weak self] in
            self?.onDisappear?.forEach { signal in
                signal.send(nil)
            }
            
            self?.lifecycle = .disappeared
        }
        
        runTasks = { [weak self] in
            self?.onTask?.forEach { signal in
                signal.send(nil)
            }
        }
    }
    
    func compile() {
        let setup = center.findCommandSetup()

        let events: [AnyEvent] = setup.events
        let notifies: [AnyNotify] = setup.notifies

        notifies.forEach { notify in
            self.notifies["\(notify.reducerType)"] = notify
        }

        var onAppearEvents: [AnyEvent] = []
        var onDisappearEvents: [AnyEvent] = []
        var onTaskEvents: [AnyEvent] = []
        var otherEvents: [AnyEvent] = []

        for event in events {
            switch event.lifecycle {
            case .onAppear:
                onAppearEvents.append(event)
            case .onDisappear:
                onDisappearEvents.append(event)
            case .onTask:
                onTaskEvents.append(event)
            default:
                otherEvents.append(event)
            }
        }
        
        // Granite's own `@Event`s compile through `CompileableEvent`; a wrapper another package
        // declares compiles through the public `GraniteCustomEvent` with a host onto this command.
        let properties = CompileableEventProperties(isOnline: kind.isOnline)
        reducers = events.flatMap { event -> [any GraniteEventContainer] in
            if let compileable = event as? CompileableEvent { return compileable.compile(self, properties: properties) }
            if let custom = event as? GraniteCustomEvent { return custom.compile(with: GraniteEventHost(director: self, isOnline: kind.isOnline)) }
            return []
        }

        self.onAppear = onAppearEvents.map { $0.signal }
        self.onDisappear = onDisappearEvents.map { $0.signal }
        self.onTask = onTaskEvents.map { $0.signal }
        
        if case .component = kind {
            GraniteLog("\(NAME) \(kind) | [\(reducers.count)] 🛥 | \(self.id)", level: .debug)
        }
    }
    
    public func update(_ state: Center.GenericGraniteState) {
        guard let store = center.findStore() else { return }
        store.wrappedValue = state
    }
    
    public func persistStateChanges() {
        //TODO: Debounce?
        guard let store = center.findStore() else { return }
        if store.autoSave {
            store.projectedValue.persistence.save()
        }
    }
    
    /*
     Notifies allow reducers to be fired based on another's
     completion.
     
     A GraniteComponent can request their reducers to respond
     to a Service's reducer completion, for instance a network
     call that is being made.
    */
    public func notify(_ reducerType: AnyGraniteReducer.Type, payload: AnyGranitePayload?) {
        if let notify = notifies["\(reducerType)"] {
            GraniteLog("\(NAME) \(kind) notify: [\(reducerType)] | Main 🧵?: \(Thread.isMainThread)", level: .debug)
            notify.send(payload)
        }
    }

    /// Fires every sibling reducer of the given type hosted by this command. Backs
    /// ``GraniteEffect/chain(_:payload:)``: chaining a reducer that isn't declared as an
    /// `@Event` in this center is a safe no-op.
    public func dispatch(_ reducerType: AnyGraniteReducer.Type, payload: GranitePayload?) {
        let matches = reducers.filter { $0.reducerType == reducerType }
        for container in matches {
            container.fire(payload)
        }
    }
}

extension GraniteCommand {
    func setServiceOffline() {
        self.kind = .service(.offline)
    }
}

/*
 Director Callbacks to be used in ReducerContainer
*/
extension GraniteCommand {
    
    public func getState() -> AnyGraniteState {
        return center.state
    }
    
    public func setState(_ state: AnyGraniteState) {
        guard let newState = state as? Center.GenericGraniteState else { return }
        
        self.update(newState)
    }
}

extension GraniteCommand {
    public func didRemoveObservers() {
        
    }
}
