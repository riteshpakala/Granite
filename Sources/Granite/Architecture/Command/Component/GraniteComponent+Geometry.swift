//
//  GraniteComponent+Geometry.swift
//  Granite
//
//  Created by Ritesh Pakala on 12/8/21.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation
import SwiftUI

/*
 Same behavior as lifecycleView except the State if hosting
 a @Geometry variable, will be updated with the Component's
 first GemeotryProxy.
*/
extension GraniteComponent {
    func geometryView(_ geo: AnyGeometry?, locate: Command<Self.GenericGraniteCenter>?) -> some View {
        lifecycle(view, locate: locate)
            .background(
                GeometryReader { proxy in
                    Color
                        .clear
                        .onAppear {
                        geo?.update(proxy)
                    }
                })
    }
}
