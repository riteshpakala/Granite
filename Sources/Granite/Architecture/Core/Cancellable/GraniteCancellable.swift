//
//  GraniteCancellable.swift
//  Granite
//
//  Granite's own cancellation token, independent of Combine.
//

/// A token that ends a subscription once, from any thread.
///
/// Dropping a token does **not** cancel it. A subscription belongs to the ``Prospect`` it was
/// stored in, and ends when that scope is cancelled or released, or when `cancel()` is
/// called. This is what lets `signal += { … }` inside a component's listeners discard its
/// result safely.
public class GraniteCancellable: Hashable, @unchecked Sendable {
    @usableFromInline let lock = GraniteLock()
    @usableFromInline var cancelled = false
    private var onCancel: (() -> Void)?

    /// Creates a token that runs `onCancel` the first time it is cancelled.
    public init(_ onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    init() {
        self.onCancel = nil
    }

    /// Whether `cancel()` has run.
    @inlinable
    public final var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    /// Ends the subscription. Idempotent and safe to call from any thread; the cancel work runs
    /// once, outside the token's lock.
    public final func cancel() {
        let shouldRun: Bool
        let action: (() -> Void)?
        lock.lock()
        if cancelled {
            shouldRun = false
            action = nil
        } else {
            cancelled = true
            shouldRun = true
            action = onCancel
            onCancel = nil
        }
        lock.unlock()

        guard shouldRun else { return }
        action?()
        didCancel()
    }

    /// Hands the token to a scope, which cancels it when the scope ends.
    @discardableResult
    public func store(in prospect: Prospect) -> Self {
        prospect.store(self)
        return self
    }

    /// Subclass hook, run once after cancellation, outside the lock.
    func didCancel() {}

    /// Runs `body` under the token's lock with its current cancellation state.
    @inlinable
    final func withStateLock<Result>(_ body: (_ isCancelled: Bool) -> Result) -> Result {
        lock.withLock { body(cancelled) }
    }

    public static func == (lhs: GraniteCancellable, rhs: GraniteCancellable) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
