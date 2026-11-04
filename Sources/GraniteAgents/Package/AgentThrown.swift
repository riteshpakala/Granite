import Foundation

/// The error a package's run threw, kept beside its call: the engine says a run's failure as a sentence, and a
/// refusal's kind would be lost in it.
final class AgentThrown: @unchecked Sendable {
    private let lock = NSLock()
    private var error: (any Error)?

    func keep(_ error: any Error) { lock.withLock { if self.error == nil { self.error = error } } }
    func take() -> (any Error)? { lock.withLock { defer { error = nil }; return error } }
}
