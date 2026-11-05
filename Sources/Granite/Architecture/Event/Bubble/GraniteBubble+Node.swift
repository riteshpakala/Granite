//
//  GraniteBubble+Node.swift
//  Granite
//
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation
import SwiftUI

/// The routes one `onBubble(_:)` installs, linked to the installer above it.
///
/// The installer owns its node through `@StateObject`, so a node is made once per view
/// identity rather than once per redraw. Its routes are swapped in place on every redraw,
/// which keeps the handle passed down the environment equal from one redraw to the next:
/// views reading it are not invalidated, and they still reach the latest closures.
///
/// Nothing points up the chain strongly. The handles below hold this node weakly, and this
/// node holds its parent weakly, so the only owner of a node, and of the closures its routes
/// capture, is the view that installed it.
@MainActor
final class GraniteBubbleNode: ObservableObject {
    var routes: [On] = []
    weak var parent: GraniteBubbleNode?

    /// Hands `value` to the first route keyed `(name, Value)`, checking this node and then
    /// each installer above it. Returns whether any route took it.
    func deliver<Value>(_ name: GraniteBubble.Name?, _ value: Value) -> Bool {
        var current: GraniteBubbleNode? = self
        while let node = current {
            for route in node.routes where route.type == Value.self && route.name == name {
                route.body.deliver(value)
                return true
            }
            current = node.parent
        }
        return false
    }

    /// The types routed under `name` here and above, for diagnosing a bubble whose name
    /// matched but whose type did not.
    func types(routedAs name: GraniteBubble.Name) -> [Any.Type] {
        var types: [Any.Type] = []
        var current: GraniteBubbleNode? = self
        while let node = current {
            types += node.routes.filter { $0.name == name }.map(\.type)
            current = node.parent
        }
        return types
    }

    /// Routes that can't work as written: two routes with one key, where only the first would
    /// ever run, and routes with neither a name nor a value type, which no bubble names.
    nonisolated static func problems(in routes: [On]) -> [String] {
        var seen = Set<On.Key>()
        var problems: [String] = []
        for route in routes {
            if route.name == nil, route.type == Void.self {
                problems.append("A route sends no value and has no name, so no bubble can reach it. Give it a name: .on(.name) or On(.name) { … }.")
            }
            if seen.insert(route.key).inserted == false {
                problems.append("Two routes are keyed \(route.label). Only the first would run; give each its own name.")
            }
        }
        return problems
    }
}
