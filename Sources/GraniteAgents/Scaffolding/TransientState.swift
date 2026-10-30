import Foundation
import Granite

/// A Granite state that is never persisted: it mirrors what the runtime knows right now (a loaded
/// model, a thread's phase, what is on disk) and is read again at launch. `GraniteState` is
/// `Codable`, so this codes as an empty object and reads back as the defaults; its members need
/// only `Equatable` and `Sendable`.
///
/// PIN: nothing durable lives in a transient state. What must survive a launch — the projects a
/// person opened — has its own persisted `Store`; everything else is a fact of
/// the machine, re-read, never trusted from a file.
public protocol TransientState: GraniteState {}

extension TransientState {
    public init(from decoder: Decoder) throws { self.init() }
    public func encode(to encoder: Encoder) throws { _ = encoder.container(keyedBy: NoKeys.self) }
}
