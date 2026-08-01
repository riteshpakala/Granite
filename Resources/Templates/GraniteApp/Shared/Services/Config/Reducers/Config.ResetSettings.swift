import Granite

extension ConfigService {
    struct ResetSettings: GraniteReducer {
        typealias Center = ConfigService.Center

        func reduce(state: inout Center.State) {
            let launchCount = state.launchCount
            let lastOpenedAt = state.lastOpenedAt

            state = .init()
            state.launchCount = launchCount
            state.lastOpenedAt = lastOpenedAt
        }
    }
}
