//
//  GraniteBubble.swift
//  Granite
//
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation
import SwiftUI

/// The handle a view calls to send an action up its view tree, to the nearest ancestor that
/// routes it with `onBubble(_:)`.
///
/// A view reads it from the environment once, no matter how many actions it sends:
///
/// ```swift
/// struct SearchBar: View {
///     @Environment(\.graniteBubble) var bubble
///     @State var query = ""
///
///     var body: some View {
///         TextField("Search", text: $query)
///             .onSubmit { bubble(.search, query) }
///     }
/// }
/// ```
///
/// A tap needs no declaration at all: `bubble(_:)` sends
/// when the view is tapped.
///
/// A route is found by its key, an optional ``Name`` plus the exact type of the value sent.
/// Each call returns whether a route took it, so a view can fall back when nothing above it
/// handles the action:
///
/// ```swift
/// if !bubble(.showDrawer, comment) { ModalService.shared.showThreadDrawer(comment) }
/// ```
///
/// The handle holds the installer's node weakly. A copy that outlives the view that installed
/// the routes (a coordinator, a closure kept by a manager) keeps none of them alive, and
/// bubbles nowhere once that view is gone.
public struct GraniteBubble: Sendable, Equatable {
    weak var node: GraniteBubbleNode?

    /// A handle that routes nowhere until replaced by one read from the environment, for
    /// objects such as a representable's coordinator that are handed the real handle later
    /// (from `context.environment.graniteBubble`).
    public init() {
        self.node = nil
    }

    init(node: GraniteBubbleNode?) {
        self.node = node
    }

    /// Tells apart actions that send the same type, and names actions that send no value.
    ///
    /// Declare names once, as constants:
    ///
    /// ```swift
    /// extension GraniteBubble.Name {
    ///     static let edit: Self = "edit"
    /// }
    /// ```
    public struct Name: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.rawValue = value
        }

        public var description: String {
            rawValue
        }
    }

    /// Sends a named action that carries no value.
    @MainActor
    @discardableResult
    public func callAsFunction(_ name: Name) -> Bool {
        send(name, ())
    }

    /// Sends a value, routed by its type alone.
    @MainActor
    @discardableResult
    public func callAsFunction<Value>(_ value: Value) -> Bool {
        send(nil, value)
    }

    /// Sends a value under a name, for when several actions send the same type.
    @MainActor
    @discardableResult
    public func callAsFunction<Value>(_ name: Name, _ value: Value) -> Bool {
        send(name, value)
    }

    @MainActor
    @discardableResult
    func send<Value>(_ name: Name?, _ value: Value) -> Bool {
        if let node, node.deliver(name, value) {
            return true
        }
        #if DEBUG
        if let name, let types = node?.types(routedAs: name), types.isEmpty == false {
            GraniteLog("bubble .\(name) sent \(Value.self), but the routes named .\(name) above take "
                       + types.map { "\($0)" }.joined(separator: ", ")
                       + ". Routes match the exact type sent: cast the value to the route's type.",
                       level: .warning)
            return false
        }
        #endif
        GraniteLog("bubble \(name?.rawValue ?? "(unnamed)") of \(Value.self) reached no route",
                   level: .debug)
        return false
    }

    public static func == (lhs: GraniteBubble, rhs: GraniteBubble) -> Bool {
        lhs.node === rhs.node
    }
}

public struct GraniteBubbleKey: EnvironmentKey {
    public static var defaultValue: GraniteBubble { GraniteBubble() }
}

public extension EnvironmentValues {
    /// The bubble handle of the nearest `onBubble(_:)` above this view.
    var graniteBubble: GraniteBubble {
        get { self[GraniteBubbleKey.self] }
        set { self[GraniteBubbleKey.self] = newValue }
    }
}
