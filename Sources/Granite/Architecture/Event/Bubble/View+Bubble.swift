//
//  View+Bubble.swift
//  Granite
//
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation
import SwiftUI

/// Collects the routes written inside `onBubble(_:)`.
///
/// Each line is a route: `On(…) { … }` for a closure, or `reducer.on(…)` for a reducer.
/// Conditions belong inside a route's closure; the list itself is fixed.
@resultBuilder
public enum GraniteBubbleBuilder {
    public static func buildExpression(_ route: On) -> On {
        route
    }

    @available(*, unavailable, message: "route a reducer with .on(…), e.g. center.save.on(.save)")
    public static func buildExpression<Expedition: GraniteReducer>(_ reducer: GraniteReducerExecutable<Expedition>) -> On {
        fatalError("unavailable")
    }

    public static func buildBlock(_ routes: On...) -> [On] {
        routes
    }
}

extension View {
    /// Handles the actions views below this one send with `bubble`, however deep they are.
    ///
    /// The nearest installer with a matching route takes an action; an action no route here
    /// matches passes on to the installers above. Views in between forward nothing.
    ///
    /// ```swift
    /// PostCard(post: post)
    ///     .onBubble {
    ///         center.upvote.on(.upvote) { (post: Post) in Vote.Meta(post: post, direction: .up) }
    ///         center.refresh.on(.refresh)
    ///         On(.goToThread) { showThread(post) }
    ///         On { (community: Community) in open(community) }
    ///     }
    /// ```
    ///
    /// Two routes with the same key trap in debug builds.
    public func onBubble(@GraniteBubbleBuilder _ routes: () -> [On]) -> some View {
        modifier(GraniteBubbleInstaller(routes: routes()))
    }

    /// Sends a named action that carries no value when this view is tapped.
    public func bubble(_ name: GraniteBubble.Name) -> some View {
        modifier(GraniteBubbleTap(name: name, value: ()))
    }

    /// Sends `value`, routed by its type alone, when this view is tapped.
    public func bubble<Value>(_ value: Value) -> some View {
        modifier(GraniteBubbleTap(name: nil, value: value))
    }

    /// Sends `value` under `name` when this view is tapped.
    public func bubble<Value>(_ name: GraniteBubble.Name, _ value: Value) -> some View {
        modifier(GraniteBubbleTap(name: name, value: value))
    }
}

struct GraniteBubbleInstaller: ViewModifier {
    let routes: [On]

    @Environment(\.graniteBubble) private var outer
    @StateObject private var node = GraniteBubbleNode()

    func body(content: Content) -> some View {
        #if DEBUG
        let problems = GraniteBubbleNode.problems(in: routes)
        if problems.isEmpty == false {
            assertionFailure(problems.joined(separator: "\n"))
        }
        #endif
        node.routes = routes
        node.parent = outer.node
        return content.environment(\.graniteBubble, GraniteBubble(node: node))
    }
}

struct GraniteBubbleTap<Value>: ViewModifier {
    let name: GraniteBubble.Name?
    let value: Value

    @Environment(\.graniteBubble) private var bubble

    func body(content: Content) -> some View {
        content.onTapGesture {
            bubble.send(name, value)
        }
    }
}
