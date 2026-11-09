//
//  Event.swift
//  Granite
//
//  Created by Ritesh Pakala on 01/02/22.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation
import SwiftUI

public enum Forwarding: String {
    case before
    case after
    case none
}

public enum Lifecycle: String {
    case onAppear
    case onDisappear
    case onTask
    case none
}

public protocol AnyEvent: Bindable {
    var forwarding: Forwarding { get }
    var lifecycle: Lifecycle { get }
}

protocol CompileableEvent: Bindable {
    /// What a lifecycle (`.onAppear`, `.onTask`, `.onDisappear`) or a forwarding parent
    /// (`.before`, `.after`) sends on to fire this event's reducer.
    var emitter: GraniteEmitter<GranitePayload?> { get }
    func compile(_ coordinator: Director, properties: CompileableEventProperties) -> [any GraniteEventContainer]
}

struct CompileableEventProperties {
    var isOnline: Bool
    
    static var empty: CompileableEventProperties {
        return .init(isOnline: false)
    }
}

@propertyWrapper
public struct Event<Executable: EventExecutable>: AnyEvent {
    enum Kind {
        case keypath
        case forwarding
        case timed
        case basic
    }
    public let id: UUID = .init()

    public var wrappedValue : Executable {
        get {
            expedition
        }
        mutating set {
            expedition = newValue
        }
    }
    
    public var expedition: Executable
    public let forwarding: Forwarding
    public let lifecycle: Lifecycle

    var kind: Kind
    var interval: Double = 0.0
    
    public init(_ forwarding: Forwarding) {
        self.expedition = .init()
        self.forwarding = forwarding
        lifecycle = .none
        kind = .forwarding
    }
    
    public init(debounce interval: Double) {
        self.expedition = .init(debounce: interval)
        self.forwarding = .none
        lifecycle = .none
        kind = .basic
    }
    
    public init(throttle interval: Double) {
        self.expedition = .init(throttle: interval)
        self.forwarding = .none
        lifecycle = .none
        kind = .basic
    }
    
    public init(_ lifecycle: Lifecycle = .none) {
        self.expedition = .init()
        self.forwarding = .none
        self.lifecycle = lifecycle
        kind = .basic
    }
    
}

extension CompileableEvent {
    func compile(_ coordinator: Director) -> [any GraniteEventContainer] {
        return compile(coordinator, properties: .empty)
    }
}

extension Event: CompileableEvent {
    var emitter: GraniteEmitter<GranitePayload?> {
        expedition.emitter
    }

    //TODO: profile
    func compile(_ coordinator: Director, properties: CompileableEventProperties) -> [any GraniteEventContainer] {
        let container: ReducerContainer<Executable>
        
        switch kind {
        case .timed:
            container = .init(expedition, isTimed: interval > 0.0, interval: interval, isOnline: properties.isOnline)
        case .forwarding, .basic, .keypath:
            container = .init(expedition, isOnline: properties.isOnline)
            
        }
        
        container.setup(coordinator)
        
        var containers: [any GraniteEventContainer] = [container]
        
        
        //TODO: allow expeditions to host events within them
        //Caveats, slow component boot times and state component mismatch
        for event in expedition.events {
            if let custom = event as? GraniteCustomEvent {
                containers += custom.compile(with: GraniteEventHost(director: coordinator, isOnline: properties.isOnline))
                continue
            }
            guard let compileableEvent = event as? CompileableEvent else {
                continue
            }
            containers += compileableEvent.compile(coordinator, properties: properties)

            //For event forwarding
            guard event.forwarding != .none else {
                continue
            }
            container.sideEffects[event.forwarding, default: []].append(compileableEvent.emitter)
        }
        
        return containers
    }
}
