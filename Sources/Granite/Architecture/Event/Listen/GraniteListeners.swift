//
//  GraniteListeners.swift
//  Granite
//
//  The handlers `listen` registers, owned by whoever listens and never by what they listen to.
//

import Foundation

/// A `listen` handler. It runs on the main actor, because listeners update views.
typealias GraniteListenHandler = @MainActor @Sendable (GranitePayload?) -> Void

/// One `listen` handler.
///
/// The emitter it listens to holds it weakly; the ``GraniteListeners`` set that registered it is
/// its only owner. Dropping the set therefore ends the subscription and releases the handler,
/// along with the view or component it captured.
final class GraniteListenerBox: GraniteEmitterDisplaceable {
    private let handler: GraniteLocked<GraniteListenHandler?>

    init(_ handler: @escaping GraniteListenHandler) {
        self.handler = GraniteLocked(handler)
    }

    /// Called on the sender's thread. Runs the handler on the main actor, inline when the sender
    /// is already on the main thread. The handler is looked up again there, so one dropped
    /// between the send and the hop does not run.
    func deliver(_ payload: GranitePayload?) {
        GraniteMain.run { [weak self] in
            guard let handler = self?.handler.withLock({ $0 }) else { return }
            handler(payload)
        }
    }

    /// Releases the handler: another listener took this one's place, or its set was cleared.
    func displaced() {
        handler.withLock { $0 = nil }
    }
}

/// The handlers one owner registered with `listen`: a component on screen, a hosted command's
/// `listen(_:_:)` key, or a reducer listened to outside any `listeners` body.
///
/// A component's set lives in SwiftUI state beside the view, so the owning chain is
/// SwiftUI → set → handlers → component → command, and nothing points back up it: when SwiftUI
/// drops the view, everything goes, whether or not `onDisappear` ran.
final class GraniteListeners: Sendable {
    /// The set `listen` registers into while a `listeners` body runs.
    ///
    /// Held weakly: a `Task` started inside the body inherits this value, and must not keep the
    /// set, its handlers or the component they capture alive. A `listen` made after the set is
    /// gone registers nowhere.
    struct Binding: Sendable {
        weak var set: GraniteListeners?
        let isBound: Bool
    }

    @TaskLocal static var bound = Binding(set: nil, isBound: false)

    /// Which registration a handler fills: one per reducer, kind and name.
    struct Slot: Hashable, Sendable {
        enum Kind: String, Sendable {
            case broadcast
            case beam
            case bubble
        }

        let executable: UUID
        let kind: Kind
        let name: String

        /// The emitter key, so two owners listening under one slot replace each other: the most
        /// recent listener wins, as it always has.
        var key: GraniteEmitterKey {
            GraniteEmitterKey("granite.listen.\(executable.uuidString).\(kind.rawValue).\(name)")
        }
    }

    private let boxes = GraniteLocked<[Slot: GraniteListenerBox]>([:])

    init() {}

    /// Replaces what an earlier `bind` registered with what `body` registers now.
    func bind(_ body: () -> Void) {
        clear()
        Self.$bound.withValue(Binding(set: self, isBound: true), operation: body)
    }

    /// Releases every handler this set registered.
    func clear() {
        let dropped = boxes.withLock { boxes -> [GraniteListenerBox] in
            let dropped = Array(boxes.values)
            boxes.removeAll()
            return dropped
        }
        for box in dropped {
            box.displaced()
        }
    }

    /// Registers `handler` under `slot` on `emitter`, releasing whatever this set held there.
    func register(_ slot: Slot,
                  on emitter: GraniteEmitter<GranitePayload?>,
                  handler: @escaping GraniteListenHandler) {
        let box = GraniteListenerBox(handler)
        let previous = boxes.withLock { $0.updateValue(box, forKey: slot) }
        previous?.displaced()
        emitter.on(box, key: slot.key) { box, payload in
            box.deliver(payload)
        }
    }

    /// How many handlers this set holds.
    var count: Int {
        boxes.withLock { $0.count }
    }
}

/// The SwiftUI side keeps a set in `@StateObject`, which needs an `ObservableObject`. The set
/// publishes nothing, so views reading it are never invalidated by it.
extension GraniteListeners: ObservableObject {}
