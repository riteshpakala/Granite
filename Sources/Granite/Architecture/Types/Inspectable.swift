//
//  Bindable.swift
//  Granite
//
//  Created by Ritesh Pakala on 12/12/21.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation

public protocol Inspectable {
    var id: UUID { get }
    func didRemoveObservers() -> Void
}

extension Inspectable {
    func removeObservers(includeChildren: Bool = false) {
        Prospector.shared.node(for: id)?.remove(includeChildren: includeChildren)
        didRemoveObservers()
    }
    
    func withObservation(_ id: UUID, _ block: (() -> Void)) {
        
    }
    
    public var prospect: Prospect? {
        Prospector.shared.node(for: self.id)
    }
}
