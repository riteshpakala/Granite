//
//  StatePersistence.swift
//  Granite
//
//  Created by Ritesh Pakala on 12/10/21.
//  Copyright © 2020 Stoic Collective, LLC. All rights reserved.
//

import Foundation

/*
 Sets a persistency type to be enabled along with a GraniteState
 for saving and retrieval operations.

 Reads/decodes happen off the main thread on the store's serial write queue; the resulting
 state is always applied back on the main thread, because the store's `@Published`
 properties must never be mutated from a background thread.
*/
public struct StatePersistence<State: Codable>: @unchecked Sendable {

    private let storage: AnyPersistence

    private let getState: @Sendable () -> State
    private let setState: @Sendable (State) -> Void

    private let isLoaded: @Sendable (Bool) -> Void

    init(storage: AnyPersistence,
         get: @escaping @Sendable () -> State,
         set: @escaping @Sendable (State) -> Void,
         loaded: @escaping @Sendable (Bool) -> Void) {
        self.storage = storage
        self.getState = get
        self.setState = set
        self.isLoaded = loaded
    }

    public func save(_ state: State? = nil) {
        storage.save(state: state ?? getState())
    }

    /// Restores persisted state asynchronously. The decode runs on the storage's serial
    /// write queue and the result is applied on the main thread. `wait` is retained for
    /// source compatibility but **no longer blocks the caller** — blocking the main thread
    /// on disk I/O was the previous behavior and is what this rewrite removes.
    public func restore(wait: Bool = false) {
        guard storage.hasRestored == false else { return }
        GraniteLog("restoring store: \(storage.key)", level: .debug)

        let storage = self.storage
        let getState = self.getState
        let setState = self.setState
        let isLoaded = self.isLoaded

        storage.readWriteQueue?.addBarrierBlock {
            let restored: State? = try? storage.restore()

            // @Published must only be mutated on the main thread.
            DispatchQueue.main.async {
                if let restored {
                    setState(restored)
                } else {
                    // No file (or unreadable) — seed disk with current defaults.
                    storage.save(state: getState())
                }
                isLoaded(true)
            }
        }
    }

    /// Kept for source compatibility; delegates to the non-blocking ``restore(wait:)``.
    public func forceRestore() {
        restore()
    }

    public func purge() {
        storage.purge()
    }

}
