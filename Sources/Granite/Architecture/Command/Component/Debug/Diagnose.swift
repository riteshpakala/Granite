//
//  Diagnose.swift
//  Granite
//
//  Created by Ritesh Pakala on 12/8/21.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation

/// Prints the live scope tree when fired. Not wired up by default.
struct DiagnoseTree<C: GraniteCenter>: GraniteReducer {
    typealias Center = C
    
    init() {}
    
    func reduce(state: inout Center.GenericGraniteState) {
        print("""
        Granite scopes: \(Prospector.nodeCount) live, \(Prospector.roots.count) top-level
        ===============================
        \(Prospector.dump())
        """)
    }
}
