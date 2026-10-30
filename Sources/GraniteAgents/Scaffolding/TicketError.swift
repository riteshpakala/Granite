import Foundation

/// What a ticket can say besides its value.
public enum TicketError: Error, Equatable, CustomStringConvertible {
    /// A second `wait` on a ticket someone is already waiting on.
    case alreadyAwaited(UUID)
    /// The callee refused the request: busy, not ready, not open (`reduce` said no).
    case refused(String)

    public var description: String {
        switch self {
        case .alreadyAwaited(let id): return "ticket \(id) is already awaited"
        case .refused(let why): return why
        }
    }
}
