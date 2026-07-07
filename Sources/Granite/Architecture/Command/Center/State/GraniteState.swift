//
//  GraniteState.swift
//  Granite
//
//  Created by Ritesh Pakala on 12/10/21.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

public protocol AnyGraniteState: Sendable {

}

/// A component's or service's state: a `Codable`, `Equatable`, `Sendable` value type.
///
/// Because state is a value, reducers freely mutate a copy and only the final value is published
/// to SwiftUI. Conforming to `Codable` also makes the state persistable via ``Store``.
public protocol GraniteState: AnyGraniteState, Findable, GraniteModel {
    init()
}

public enum GraniteSignalError: Error {
    case test
}
