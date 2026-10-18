//
//  Command.swift
//  Granite
//
//  Created by Ritesh Pakala on 12/12/21.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation
import SwiftUI

@propertyWrapper
public struct Command<C: GraniteCenter> : DynamicProperty {
    public var id : UUID {
        command.id
    }

    public var wrappedValue : C {
        get {
            command.center
        }
        mutating set {
            command.update(newValue.state)
        }
    }
    
    public var projectedValue : GraniteCommand<C> {
        command
    }
    
    var didAppear: (() -> Void)? {
        command.didAppear
    }
    var didDisappear: (() -> Void)? {
        command.didDisappear
    }
    var runTasks: (() -> Void)? {
        command.runTasks
    }
    
    //TODO: used to be StoreObject/ObservedObject,
    //Observed object was not propagating changes in a nested view
    @StateObject public var command : GraniteCommand<C>

    /// The enclosing component's or pushed screen's scope.
    @Environment(\.graniteProspect) private var parentProspect

    public init() {
        _command = .init(wrappedValue: .init(.component))
    }
    
    public init(_ state: C.GenericGraniteState) {
        // Built inside the autoclosure so the center is constructed once, when SwiftUI first
        // installs the view — not on every re-init of the enclosing struct.
        _command = .init(wrappedValue: {
            var initialCenter: C = .init()
            initialCenter.state = state
            return GraniteCommand(.component, initialCenter: initialCenter)
        }())
    }

    /// Joins the command's scope to the one in the environment. After the first update this
    /// is an identity check.
    public mutating func update() {
        guard let parentProspect else { return }
        // SwiftUI calls `update()` on the main thread; the box carries the `@StateObject`
        // storage into the main-actor read without sending `self`.
        let storage = MainThreadBox(_command)
        MainActor.assumeIsolated {
            let prospect = storage.value.wrappedValue.prospect
            if prospect.parent !== parentProspect {
                prospect.attach(to: parentProspect)
            }
        }
    }
}

/// Carries a main-thread-only value into `MainActor.assumeIsolated`.
private struct MainThreadBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
