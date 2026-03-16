//
//  GraniteScene.swift
//  Granite
//
//  Created by Ritesh Pakala on 11/9/24.
//

import SwiftUI

public protocol GraniteScene: Scene {
    associatedtype GenericGraniteCenter: GraniteCenter
    var center: GenericGraniteCenter { get set }
}

public extension GraniteScene {
    static var id: String {
        String(describing: self)
    }
}
