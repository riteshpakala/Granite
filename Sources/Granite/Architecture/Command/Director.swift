//
//  Director.swift
//  Granite
//
//  Created by Ritesh Pakala on 07/04/22.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation

/*
 Allows ReducerContainers to safely update state of their host
 GraniteCommands'
*/
protocol Director: AnyObject {
    /// The host's scope. Reducer containers create their own scope beneath it.
    var prospect: Prospect { get }
    var lifecycle: GraniteLifecycle { get set }
    var reducers: [any GraniteEventContainer] { get set }
    func persistStateChanges()
    func getState() -> AnyGraniteState
    func setState(_ state: AnyGraniteState)
    func notify(_ reducerType: AnyGraniteReducer.Type, payload: AnyGranitePayload?)
    /// Fires a sibling reducer of the given type in this command, used by
    /// ``GraniteEffect/chain(_:payload:)`` to chain reducers within a center.
    func dispatch(_ reducerType: AnyGraniteReducer.Type, payload: GranitePayload?)
}

extension Director {
    var isAvailable: Bool {
        lifecycle.isAvailable
    }
}
