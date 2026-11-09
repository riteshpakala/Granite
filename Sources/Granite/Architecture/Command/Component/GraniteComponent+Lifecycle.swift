//
//  GraniteComponent+Lifecycle.swift
//  Granite
//
//  Created by Ritesh Pakala on 12/8/21.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation
import SwiftUI

/*
 Primarily used for Component/Service lifecycle debugging
 and observation.
*/
enum GraniteLifecycle: String, Equatable, Codable {
    case attached
    case deAttached

    case appeared
    case disappeared
    case deLink

    case none

    var isAvailable: Bool {
        switch self {
        case .attached, .appeared:
            return true
        default:
            return false
        }
    }
}

extension GraniteComponent {
    @ViewBuilder
    func lifecycle<Body : View>(_ view : Body, locate: Command<Self.GenericGraniteCenter>?) -> some View {
        let relays = self.findRelays()

        if let command = locate?.command {
            view.modifier(GraniteComponentLifecycle(command: command,
                                                    relays: relays,
                                                    listeners: { self.listeners }))
        } else {
            view.modifier(GraniteRelayLifecycle(relays: relays))
        }
    }
}

/// A component's appearance, tasks and disappearance, and the listeners it registers while on
/// screen.
///
/// The listener set lives here, in SwiftUI state, and not in the command: SwiftUI owns the set,
/// the set owns the handlers, and the handlers own the component they capture. Nothing points
/// back up that chain, so when SwiftUI drops the view all of it goes, even if `onDisappear`
/// never ran.
struct GraniteComponentLifecycle<Center: GraniteCenter>: ViewModifier {
    let command: GraniteCommand<Center>
    let relays: [AnyRelay]
    let listeners: @MainActor () -> Void

    @StateObject private var listenerSet = GraniteListeners()

    func body(content: Content) -> some View {
        if #available(macOS 12.4, iOS 15, *) {
            content
                .task {
                    awake()
                    command.runTasks?()
                }
                .onAppear {
                    appear()
                }
                .onDisappear {
                    disappear()
                }
        } else {
            content
                .onAppear {
                    awake()
                    appear()
                }
                .onDisappear {
                    disappear()
                }
        }
    }

    private func appear() {
        // Listeners first, so a reducer the appearance fires cannot send before they are in
        // place. Binding again replaces what an earlier appearance registered.
        let listeners = self.listeners
        listenerSet.bind {
            listeners()
        }
        GraniteLog("applying listeners to: \(command.NAME)", level: .debug)
        command.didAppear?()
    }

    private func disappear() {
        command.didDisappear?()
        for relay in relays {
            relay.silence()
        }
        listenerSet.clear()
    }

    private func awake() {
        for relay in relays {
            relay.awake()
        }
    }
}

/// A component without a `@Command`: only its relays follow it on and off screen.
struct GraniteRelayLifecycle: ViewModifier {
    let relays: [AnyRelay]

    func body(content: Content) -> some View {
        content
            .onAppear {
                for relay in relays {
                    relay.awake()
                }
            }
            .onDisappear {
                for relay in relays {
                    relay.silence()
                }
            }
    }
}
