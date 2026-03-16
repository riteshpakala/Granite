//
//  Service.swift
//  Granite
//
//  Created by Ritesh Pakala on 12/12/21.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation
import SwiftUI

@propertyWrapper
public struct Service<Center: GraniteCenter> : DynamicProperty {
    public var id : UUID {
        command.id
    }

    public var wrappedValue : Center {
        get {
            command.center
        }
        mutating set {
            command.update(newValue.state)
        }
    }
    
    public var projectedValue : GraniteCommand<Center> {
        command
    }

    public var command : GraniteCommand<Center>
    
    public init(_ kind: GraniteRelayKind = .offline) {
        command = .init(.service(kind))
    }
    
    public init(_ kind: GraniteRelayKind = .offline, state: Center.GenericGraniteState) {
        var initialCenter: Center = .init()
        initialCenter.state = state
        command = .init(.service(kind), initialCenter: initialCenter)
    }
}
