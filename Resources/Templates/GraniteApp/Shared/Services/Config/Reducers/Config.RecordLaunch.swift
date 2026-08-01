import Foundation
import Granite

extension ConfigService {
    struct RecordLaunch: GraniteReducer {
        typealias Center = ConfigService.Center

        func reduce(state: inout Center.State) {
            state.launchCount += 1
            state.lastOpenedAt = Date()
        }
    }
}
