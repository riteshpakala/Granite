//
//  GraniteRelay.swift
//  Granite
//
//  Created by Ritesh Pakala on 12/12/21.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

/*
 NOTE: All relays are online now with the introduction of `SharedObject`
 
 If a GraniteRelay is online, when 1 relay is updated
 all components using the same relay and observing the same
 changing properties will update simultaneously
*/
public enum GraniteRelayKind {
    case online
    case offline
}

/*
 A GraniteRelay allows a GraniteService to be readily available
 in Components and/or Reducers. When inside components changes
 will propogate view changes.
*/
final public class GraniteRelay<Service: GraniteService>: Inspectable, Prospectable, Findable, Director, SharableObject, Nameable {
    public static var initialValue: GraniteRelay<Service> {
        .init()
    }
    
    public let id : UUID = .init()
    
    var service: Service
    
    var lifecycle: GraniteLifecycle = .none
    
    internal var isSilenced: Bool = false
    
    fileprivate var behavior: GraniteRelayBehavior = .normal
    
    internal var reducers: [AnyReducerContainer] = []
    internal var cancellables = Set<AnyCancellable>()
    
    fileprivate var kind: GraniteRelayKind
    fileprivate var isDiscoverable: Bool
    
    init(isDiscoverable: Bool = false) {
        self.kind = .offline
        self.isDiscoverable = isDiscoverable
        
        Prospector.shared.currentNode?.addChild(id: self.id,
                                                label: String(reflecting: Service.self),
                                                type: .relay)
        Prospector.shared.push(id: self.id, .relay)
        service = Service()
        setup()
        Prospector.shared.pop(.relay)
    }
    
    deinit {
        //GraniteLog("relay deinit 🛸: \(NAME)", level: .debug)
        removeObservers(includeChildren: true)
        cancellableBag.forEach { $0.cancel() }
        cancellableBag.removeAll()
    }
    
    //deprecated
    public func sharableLoaded() {
        service.center.findStore()?.restore()
    }
    
    public func update(behavior: GraniteRelayBehavior) {
        self.behavior = behavior
    }
    
    public func update(_ state: Service.GenericGraniteCenter.GenericGraniteState) {
        guard let store = service.center.findStore() else { return }
        store.wrappedValue = state
    }
    
    func setup() {
        //GraniteLog("relay setting up 🛸: \(NAME)", level: .debug)
        bind()
        observe()
    }
    
    func bind() {
        let events = self.findCompileableEvents()
        
        self.reducers = events.flatMap { $0.compile(self, properties: .init(isOnline: self.kind == .online)) }
    }
    var cancellableBag = Set<AnyCancellable>()
    func observe() {
        guard let store = service.center.findStore() else { return }
        
        store
            .container
            .objectWillChange
            // DispatchQueue.main, not RunLoop.main: RunLoop.main only fires in the default
            // run-loop mode, so relay-backed UI stalled during touch tracking. Matches the
            // fix already applied to GraniteCommand's component observer.
            .throttle(for: .seconds(0.0167), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellableBag)
        
        guard isDiscoverable else { return }
        
        self.lifecycle = .attached
    }
    
    public func awake() {
        isSilenced = false
    }
    
    public func silence() {
        isSilenced = true
    }
    
    public func persistStateChanges() {
        service.locate?.command.persistStateChanges()
    }
    
    public func notify(_ reducerType: AnyGraniteReducer.Type, payload: AnyGranitePayload?) {
        service.locate?.command.notify(reducerType, payload: payload)
    }

    /// Chains a sibling reducer within the relay's own reducer set (backs
    /// ``GraniteEffect/chain(_:payload:)`` for service reducers).
    public func dispatch(_ reducerType: AnyGraniteReducer.Type, payload: GranitePayload?) {
        let matches = reducers.filter { $0.reducerType == reducerType }
        for container in matches {
            container.fire(payload)
        }
    }
}

//MARK: Network sharing
extension GraniteRelay {
    
}

extension GraniteRelay {
    public func getState() -> AnyGraniteState {
        return service.center.state
    }
    
    public func setState(_ state: AnyGraniteState) {
        guard let newState = state as? Service.GenericGraniteCenter.GenericGraniteState else { return }
        
        self.update(newState)
    }
}

extension GraniteRelay {
    public func didRemoveObservers() {
        
    }
}

//TODO: Granite relay network is not syncing states
