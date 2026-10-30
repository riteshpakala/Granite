//  WHAT: A typed reply slot for a ticketed dispatch. A caller opens a ticket, sends a reducer the
//        ticket's id in its payload, and awaits the value the reducer's effect resolves it with:
//        the dispatch stays visible in the callee's reducers and state, and the caller gets a value.
//  PIN:  OPEN BEFORE SEND. A resolve that lands before `wait` is kept in the slot, so there is no
//        window in which a fast reducer resolves into nothing. Cancelling the waiting task cancels
//        the ticket; the effect still runs to completion and its late resolve is dropped.
//  PIN:  A SETTLE WAITS FOR MAIN. Resolve and fail let the main queue run everything sent to it before
//        them, so a write an effect made through its service's writer (a reducer that commits in the turn
//        it is sent, `thread: nil`) is in the state when the waiter wakes and reads it.

import Foundation

/// PIN: open before send, because a reply that lands before `wait` must be kept, not lost.
public actor GraniteTickets<Value: Sendable> {
    /// One reply slot, by id: what a reducer's payload carries.
    public struct Ticket: Sendable, Hashable {
        public let id: UUID
    }

    private enum Slot {
        case open
        case waiting(CheckedContinuation<Value, any Error>)
        case settled(Result<Value, any Error>)
    }

    private var slots: [UUID: Slot] = [:]

    public init() {}

    /// A new slot, open: call before sending the payload that carries its id.
    public func open() -> Ticket {
        let ticket = Ticket(id: UUID())
        slots[ticket.id] = .open
        return ticket
    }

    /// Suspends until the ticket is resolved or failed.
    public func wait(_ id: UUID) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
                switch slots[id] {
                case .settled(let result)?:
                    slots[id] = nil
                    continuation.resume(with: result)
                case .open?:
                    slots[id] = .waiting(continuation)
                case .waiting?:
                    continuation.resume(throwing: TicketError.alreadyAwaited(id))
                case nil:
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    /// Answers the waiter, or keeps the value for one that has not waited yet; after the main queue has
    /// run what was sent to it before this call.
    public func resolve(_ id: UUID, with value: Value) async {
        await Self.mainQueueTurn()
        settle(id, .success(value))
    }
    /// Fails the waiter with `error`, or keeps the failure for one that has not waited yet; after the
    /// main queue has run what was sent to it before this call.
    public func fail(_ id: UUID, _ error: any Error) async {
        await Self.mainQueueTurn()
        settle(id, .failure(error))
    }
    /// Fails the waiter with `CancellationError`; a late resolve is then dropped.
    public func cancel(_ id: UUID) { settle(id, .failure(CancellationError())) }

    /// Returns once the main queue has run every block enqueued on it before the call: the writes an
    /// effect sent through `onMain` ahead of its resolve.
    private static func mainQueueTurn() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// Tickets nobody has settled and awaited yet (tests).
    public var pending: Int { slots.count }

    private func settle(_ id: UUID, _ result: Result<Value, any Error>) {
        switch slots[id] {
        case .waiting(let continuation)?:
            slots[id] = nil
            continuation.resume(with: result)
        case .open?:
            slots[id] = .settled(result)
        case .settled?, nil:
            break   // a second settle, or a cancelled ticket: dropped
        }
    }
}
