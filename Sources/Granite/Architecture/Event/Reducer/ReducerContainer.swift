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
    func setup(_ coordinator: Director)
}

//TODO: MAJOR
//When an @Event is inside a center it cannot be declared in a reducer
//Check @Event var sync: Sync.Reducer (May only be the case if the Relay/Service is in .online mode)
//infinite loop case as well
//
// 01/08/23 which is why we declare @Notify outside of reducers not within..................
//
class ReducerContainer<Event : EventExecutable>: AnyReducerContainer, Prospectable, Nameable {
    public var id : UUID = .init()
    
    public var label: String {
        reducer?.label ?? ""
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
    
    public let queue: DispatchQueue
    
    var events: [AnyEvent] {
        reducer?.events ?? []
    }
    
    var thread: DispatchQueue {
        .init(label: "\(id)", qos: .background)
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
            self.executionTask?.cancel()
            
            switch reducer?.behavior {
            case .task(let priority):
                self.executionTask = Task(priority: priority) { [weak self] in
                    await self?.executeAsync()
                }
            default:
                self.execute()
            }
        }
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
        }
        
        for signal in (sideEffects[.after] ?? []){
            signal.send(reducer?.payload as? GranitePayload)
        }
    }
    
    func updateState(_ newState: AnyGraniteState) {
        self.coordinator?.setState(newState)
        //self?.coordinator?.persistStateChanges()
        
        self.thread.async {
            if let reducerType = self.reducer?.reducerType {
                self.coordinator?.notify(reducerType,
                                         payload: self.reducer?.payload)
            }
        }
    }
}
