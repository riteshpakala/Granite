//
//  GraniteComponent+View.swift
//  Granite
//
//  Created by Ritesh Pakala on 12/8/21.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation
import SwiftUI

extension GraniteComponent {
    public var body: some View {
        let geometry = locate?.command.center.state.findGeometry()
        
        return ZStack {
            if let geometry {
                geometryView(geometry)
            } else {
                lifecycle(view)
            }
        }
    }
}
