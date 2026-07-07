import Foundation
import SwiftUI

extension Button {

    // These convenience initializers wrap a Granite action/reducer in a SwiftUI Button whose
    // action closure is main-actor isolated, so the inits are `@MainActor` (they are only
    // ever used inside view bodies).

    @MainActor
    public init(action : GraniteAction<Void>.ActionWrapper, @ViewBuilder label: () -> Label) {
        self.init {
            action.perform()
        } label: {
            label()
        }
    }

    @MainActor
    public init<I>(action : GraniteAction<I>.ActionWrapper, value : I, @ViewBuilder label: () -> Label) {
        self.init {
            action.perform(value)
        } label: {
            label()
        }
    }

    @MainActor
    public init<S: EventExecutable>(_ reducer: S, @ViewBuilder label: () -> Label) {
        self.init {
            reducer.send()
        } label: {
            label()
        }
    }

    @MainActor
    public init<S: EventExecutable, I: GranitePayload>(_ reducer: S, value : I, @ViewBuilder label: () -> Label) {
        self.init {
            reducer.send(value)
        } label: {
            label()
        }
    }
}
