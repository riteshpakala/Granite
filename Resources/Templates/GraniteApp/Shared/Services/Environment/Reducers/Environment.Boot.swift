import Foundation
import Granite

extension EnvironmentService {
    struct Boot: GraniteReducer {
        typealias Center = EnvironmentService.Center
        typealias Metadata = Meta

        struct Meta: GranitePayload {
            let isFirstLaunch: Bool
        }

        func reduce(state: inout Center.State, payload: Meta) {
            state.startedAt = Date()
            state.isFirstLaunch = payload.isFirstLaunch
            state.lastError = nil

            // This starter boot is synchronous. Coordinate long-running startup work with
            // separate async effects/events so the main actor remains responsive.
            state.phase = .ready
        }
    }
}
