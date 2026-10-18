//
//  Prospector.swift
//  Granite
//
//  The ambient scope binding plus cold-path diagnostics. Not a registry of every node.
//

import Foundation

/// Where Granite finds the scope that new subscriptions and scopes belong to.
///
/// ``current`` is a task-local value: each task (or, outside any task, each thread) sees only
/// the binding made by its own enclosing ``Prospect/withScope(_:)``. It is a static *key*,
/// not shared mutable state, so concurrent view construction never contends on it or attaches
/// to another view's scope.
///
/// `Task { }` inherits the binding. `Task.detached` and `DispatchQueue.async` do not — capture
/// the scope and call `withScope` again on the other side, or store into it explicitly.
public enum Prospector {
    @TaskLocal public static var current: Prospect? = nil

    /// Runs `body` with `prospect` bound as ``current``.
    public static func withScope<Result>(_ prospect: Prospect?, _ body: () throws -> Result) rethrows -> Result {
        try $current.withValue(prospect, operation: body)
    }

    static let registry = ProspectRegistry()

    // MARK: Diagnostics (cold path)

    /// Live top-level scopes: relays, navigation entries, and commands not yet attached to a
    /// parent. Only scope creation, re-parenting and teardown touch this list — never
    /// observing, sending, or redrawing.
    public static var roots: [Prospect] {
        registry.snapshot()
    }

    /// Every live scope reachable from ``roots``.
    public static var nodeCount: Int {
        var visited = Set<ObjectIdentifier>()
        var stack = roots
        while let node = stack.popLast() {
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            stack.append(contentsOf: node.childScopes)
        }
        return visited.count
    }

    /// Finds a live scope by id by walking the tree. O(n); meant for debugging tools.
    public static func find(id: UUID) -> Prospect? {
        var visited = Set<ObjectIdentifier>()
        var stack = roots
        while let node = stack.popLast() {
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            if node.id == id { return node }
            stack.append(contentsOf: node.childScopes)
        }
        return nil
    }

    /// An indented outline of the live tree.
    public static func dump() -> String {
        var lines: [String] = []
        var visited = Set<ObjectIdentifier>()

        func visit(_ node: Prospect, depth: Int) {
            guard visited.insert(ObjectIdentifier(node)).inserted else { return }
            let indent = String(repeating: "  ", count: depth)
            lines.append("\(indent)\(node.type) \(node.label) [subs: \(node.subscriptionCount)]")
            for child in node.childScopes.sorted(by: { $0.label < $1.label }) {
                visit(child, depth: depth + 1)
            }
        }

        for root in roots.sorted(by: { $0.label < $1.label }) {
            visit(root, depth: 0)
        }
        return lines.joined(separator: "\n")
    }
}

/// Weak list of top-level scopes, for diagnostics only.
final class ProspectRegistry: @unchecked Sendable {
    private let lock = GraniteLock()
    private var entries: [ObjectIdentifier: WeakProspect] = [:]

    func insert(_ prospect: Prospect) {
        lock.withLock { entries[ObjectIdentifier(prospect)] = WeakProspect(prospect) }
    }

    func remove(_ key: ObjectIdentifier) {
        lock.withLock { _ = entries.removeValue(forKey: key) }
    }

    func snapshot() -> [Prospect] {
        lock.withLock { entries.values.compactMap(\.value) }
    }
}
