//
//  GraniteCommand+Hosting.swift
//  Granite
//
//  Created by Ritesh Pakala on 7/20/26.
//

import Foundation

/*
 Non-SwiftUI hosting support.

 `@Command` retains its GraniteCommand via `@StateObject`, which only
 resolves inside a SwiftUI render pass. External renderers (e.g. Concrete's
 server-side web runtime) need to construct and drive a `.component`
 command themselves: build it with `hosted(...)`, retain it, and mirror
 `GraniteComponent+Lifecycle` by calling `appear()` / `performTasks()`
 when the component enters the tree and `disappear()` when it leaves.
*/
extension GraniteCommand {
    /// Creates a fully wired `.component` command outside of SwiftUI —
    /// identical to what `@Command` builds, minus SwiftUI retention.
    /// The caller owns the instance.
    public static func hosted(initialCenter: Center? = nil) -> GraniteCommand<Center> {
        GraniteCommand<Center>(.component, initialCenter: initialCenter)
    }

    /// Creates a hosted `.component` command seeded with an initial state.
    public static func hosted(state: Center.GenericGraniteState) -> GraniteCommand<Center> {
        var center = Center()
        center.state = state
        return GraniteCommand<Center>(.component, initialCenter: center)
    }

    /// Fires `@Event(.onAppear)` reducers, mirroring the `.onAppear`
    /// half of `GraniteComponent+Lifecycle`.
    public func appear() {
        didAppear?()
    }

    /// Fires `@Event(.onDisappear)` reducers, mirroring the `.onDisappear`
    /// half of `GraniteComponent+Lifecycle`.
    public func disappear() {
        didDisappear?()
    }

    /// Fires `@Event(.onTask)` reducers, mirroring the `.task`
    /// half of `GraniteComponent+Lifecycle`.
    public func performTasks() {
        runTasks?()
    }
}
