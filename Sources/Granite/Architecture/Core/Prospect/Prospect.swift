//
//  Prospect.swift
//  Granite
//
//  A node in Granite's ownership tree. Subscriptions are stored in a scope, and ending the
//  scope ends them and everything beneath it, in the manner of a responder chain.
//

import Foundation

public enum ProspectType: String, Sendable {
    case root
    case command
    case center
    case relay
    case relayNetwork
    case event
    case expedition
    case signal
    case state
    case listeners
    case none
    case navigation
    case custom
}

/// A scope that owns subscriptions and child scopes.
///
/// **Ownership.** Whatever creates a scope (a command, a reducer container, a relay, a
/// navigation entry, a listener set) holds it strongly. A parent holds its children *weakly*,
/// so a scope lives exactly as long as its owner. There is no global index: nothing outside
/// the owner keeps a scope alive.
///
/// **Teardown.** ``cancel()`` cancels every stored token and every live child, then detaches
/// from the parent. It is terminal: a token stored afterwards is cancelled at once. Releasing
/// the last reference to a scope does the same.
///
/// **Threading.** Every scope has its own lock, held only to read or swap its own fields.
/// No method calls out to tokens, children or parents while holding it, so scopes on
/// different threads never contend and teardown cannot deadlock.
public final class Prospect: Hashable, CustomStringConvertible, @unchecked Sendable {
    public let id: UUID
    public let label: String
    public let type: ProspectType

    private static let minimumCompactionThreshold = 32

    private let lock = GraniteLock()
    private weak var _parent: Prospect?
    private var children: [ObjectIdentifier: WeakProspect] = [:]
    private var tokens: [GraniteCancellable] = []
    private var compactionThreshold = Prospect.minimumCompactionThreshold
    private var cancelled = false
    private var isRoot = false

    /// Creates a scope under `parent`, which defaults to the scope bound to the current task
    /// or thread (``Prospector/current``). Pass `nil` for a top-level scope.
    public init(id: UUID = UUID(),
                label: String,
                type: ProspectType,
                parent: Prospect? = Prospector.current) {
        self.id = id
        self.label = label
        self.type = type

        if let parent {
            lock.withLock { _parent = parent }
            if parent.adopt(self) == false {
                cancel()
            }
        } else {
            lock.withLock { isRoot = true }
            Prospector.registry.insert(self)
        }
    }

    deinit {
        let key = ObjectIdentifier(self)
        lock.lock()
        let bag = tokens
        let kids = children.values.compactMap(\.value)
        let parent = _parent
        let wasRoot = isRoot
        lock.unlock()

        for token in bag { token.cancel() }
        for kid in kids { kid.cancel() }
        if let parent {
            parent.release(key)
        } else if wasRoot {
            Prospector.registry.remove(key)
        }
    }

    // MARK: Scope

    /// Binds this scope as ``Prospector/current`` while `body` runs. Signals observed inside
    /// the body, and scopes created inside it, land under this scope.
    public func withScope<Result>(_ body: () throws -> Result) rethrows -> Result {
        try Prospector.withScope(self, body)
    }

    /// Creates a child scope. The caller owns the child and must keep it, since this scope
    /// holds it only weakly.
    public func child(label: String, type: ProspectType, id: UUID = UUID()) -> Prospect {
        Prospect(id: id, label: label, type: type, parent: self)
    }

    /// Stores a token so it ends with this scope. If the scope has already ended, the token is
    /// cancelled immediately.
    public func store(_ token: GraniteCancellable) {
        lock.lock()
        if cancelled {
            lock.unlock()
            token.cancel()
            return
        }
        tokens.append(token)
        if tokens.count >= compactionThreshold {
            // Long-lived scopes that cancel and re-add tokens would otherwise grow forever.
            tokens.removeAll { $0.isCancelled }
            compactionThreshold = max(Prospect.minimumCompactionThreshold, tokens.count * 2)
        }
        lock.unlock()
    }

    /// Ends every subscription in this scope and its live children, then detaches it.
    /// Idempotent and terminal.
    public func cancel() {
        lock.lock()
        guard cancelled == false else {
            lock.unlock()
            return
        }
        cancelled = true
        let bag = tokens
        tokens = []
        let kids = children.values.compactMap(\.value)
        children = [:]
        let parent = _parent
        _parent = nil
        let wasRoot = isRoot
        isRoot = false
        lock.unlock()

        for token in bag { token.cancel() }
        for kid in kids { kid.cancel() }

        let key = ObjectIdentifier(self)
        if let parent {
            parent.release(key)
        } else if wasRoot {
            Prospector.registry.remove(key)
        }
    }

    /// Moves this scope under `newParent`, or to the top level when `nil`. Attaching to an
    /// ended parent ends this scope, and attaching under one of its own descendants is
    /// ignored. Meant for one caller at a time (SwiftUI updates on the main thread).
    public func attach(to newParent: Prospect?) {
        guard newParent !== self else { return }
        if let newParent, newParent.hasAncestor(self) { return }

        lock.lock()
        if cancelled || (_parent === newParent && (newParent != nil || isRoot)) {
            lock.unlock()
            return
        }
        let oldParent = _parent
        let wasRoot = isRoot
        _parent = newParent
        isRoot = newParent == nil
        lock.unlock()

        let key = ObjectIdentifier(self)
        if let oldParent {
            oldParent.release(key)
        } else if wasRoot {
            Prospector.registry.remove(key)
        }

        if let newParent {
            if newParent.adopt(self) == false {
                cancel()
            }
        } else {
            Prospector.registry.insert(self)
        }
    }

    // MARK: Inspection

    public var parent: Prospect? {
        lock.withLock { _parent }
    }

    public var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    /// The live child scopes, in no particular order.
    public var childScopes: [Prospect] {
        lock.withLock { children.values.compactMap(\.value) }
    }

    /// How many stored tokens are still live.
    public var subscriptionCount: Int {
        let bag = lock.withLock { tokens }
        return bag.reduce(0) { $0 + ($1.isCancelled ? 0 : 1) }
    }

    public var description: String {
        "\(type) \(label)"
    }

    public static func == (lhs: Prospect, rhs: Prospect) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    // MARK: Tree plumbing

    /// Registers `child` under this scope. Returns false if this scope has ended.
    fileprivate func adopt(_ child: Prospect) -> Bool {
        lock.withLock {
            guard cancelled == false else { return false }
            children[ObjectIdentifier(child)] = WeakProspect(child)
            return true
        }
    }

    fileprivate func release(_ key: ObjectIdentifier) {
        lock.withLock { _ = children.removeValue(forKey: key) }
    }

    private func hasAncestor(_ candidate: Prospect) -> Bool {
        var node = parent
        while let current = node {
            if current === candidate { return true }
            node = current.parent
        }
        return false
    }
}

struct WeakProspect {
    weak var value: Prospect?

    init(_ value: Prospect) {
        self.value = value
    }
}
