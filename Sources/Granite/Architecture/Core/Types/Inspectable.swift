//
//  Inspectable.swift
//  Granite
//
//  Created by Ritesh Pakala on 12/12/21.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation

/// Something with a stable identity.
public protocol Inspectable {
    var id: UUID { get }
}
