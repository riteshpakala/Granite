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

/// What a lifecycle (`.onAppear`, `.onTask`, `.onDisappear`) fires: an `@Event`'s emitter, or the
/// first container a `GraniteCustomEvent` compiled.
enum GraniteLifecycleTarget: Sendable {
    case emitter(GraniteEmitter<GranitePayload?>)
    case container(any GraniteEventContainer)

    func fire(_ payload: GranitePayload?) {
        switch self {
        case .emitter(let emitter):
            emitter.send(payload)
        case .container(let container):
            container.fire(payload)
        }
    }
}

/*
 A GraniteComponent's and GraniteService's Core event router,
 state manager, and responder.

 Nothing a command wires up needs undoing: its reducer containers receive as weak receivers,
 and listeners are owned by whoever listens. Releasing the command releases all of it, with no
 `deinit`.
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

    /// Listener sets registered through ``listen(_:_:)``, one per key. Guarded because hosts may
    /// drive appear and disappear off the main thread.
    private let listenerSets = GraniteLock<[UUID: GraniteListeners]>([:])

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

    var lifecycleTargets: [Lifecycle: [GraniteLifecycleTarget]] = [:]
    var didAppear: (() -> Void)?
    var didDisappear: (() -> Void)?
    var runTasks: (() -> Void)?

    //@Event public var discoveryDiagnostic: DiagnoseTree<Center>.Reducer
    internal var reducers: [any GraniteEventContainer] = []
    internal var notifies: [String: AnyNotify] = [:]

    fileprivate var kind: GraniteCommandKind
    public var buildBehavior: BuildBehavior

    init(_ kind: GraniteCommandKind, initialCenter: Center? = nil) {
        let id: UUID = .init()
        self.id = id
        self.thread = DispatchQueue(label: "granite.command.\(id.uuidString)", qos: .userInitiated)
        self.kind = kind
        self.buildBehavior = .none
        center = initialCenter ?? Center()
        setup()
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
        guard center.findStore() != nil else {
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
    }

    /// Runs `listeners` with a fresh listener set keyed by `id`, replacing the set an earlier
    /// call made under that key. Every handler it registers ends with ``removeListeners(_:)``,
    /// or when this command is released.
    ///
    /// SwiftUI components do not need this: their listeners live beside the view. It is for hosts
    /// that drive a command themselves (see ``hosted(initialCenter:)``).
    public func listen(_ id: UUID? = nil, _ listeners: () -> Void) {
        let key = id ?? self.id
        let set = GraniteListeners()
        let previous = listenerSets.withLock { $0.updateValue(set, forKey: key) }
        previous?.clear()

        set.bind(listeners)
        GraniteLog("applying listeners to: \(NAME)", level: .debug)
    }

    public func removeListeners(_ id: UUID? = nil) {
        let key = id ?? self.id
        let set = listenerSets.withLock { $0.removeValue(forKey: key) }
        set?.clear()
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
            guard let self else { return }
            // Non-blocking: the previous `thread.sync` synchronously blocked the main
            // thread (didAppear is invoked from SwiftUI's .onAppear) on a background queue,
            // risking priority inversion. Fire the onAppear events asynchronously instead.
            // Only the targets and the payload cross to the queue, never the command.
            let targets = self.lifecycleTargets[.onAppear] ?? []
            let payload: GranitePayload?
            if case .dependency(let dependency) = self.buildBehavior {
                payload = dependency as? GranitePayload
            } else {
                payload = nil
            }
            if targets.isEmpty == false {
                self.thread.async {
                    for target in targets {
                        target.fire(payload)
                    }
                }
            }

            self.lifecycle = .appeared
        }

        didDisappear = { [weak self] in
            for target in self?.lifecycleTargets[.onDisappear] ?? [] {
                target.fire(nil)
            }

            self?.lifecycle = .disappeared
        }

        runTasks = { [weak self] in
            for target in self?.lifecycleTargets[.onTask] ?? [] {
                target.fire(nil)
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

        // Granite's own `@Event`s compile through `CompileableEvent`; a wrapper another package
        // declares compiles through the public `GraniteCustomEvent` with a host onto this command.
        let properties = CompileableEventProperties(isOnline: kind.isOnline)
        var reducers: [any GraniteEventContainer] = []
        var lifecycleTargets: [Lifecycle: [GraniteLifecycleTarget]] = [:]

        for event in events {
            let target: GraniteLifecycleTarget?
            if let compileable = event as? CompileableEvent {
                reducers += compileable.compile(self, properties: properties)
                target = .emitter(compileable.emitter)
            } else if let custom = event as? GraniteCustomEvent {
                let containers = custom.compile(with: GraniteEventHost(director: self, isOnline: kind.isOnline))
                reducers += containers
                target = containers.first.map { .container($0) }
            } else {
                target = nil
            }

            if event.lifecycle != .none, let target {
                lifecycleTargets[event.lifecycle, default: []].append(target)
            }
        }

        self.reducers = reducers
        self.lifecycleTargets = lifecycleTargets

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
