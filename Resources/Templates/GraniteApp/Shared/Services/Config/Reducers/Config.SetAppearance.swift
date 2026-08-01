import Granite

extension ConfigService {
    struct SetAppearance: GraniteReducer {
        typealias Center = ConfigService.Center
        typealias Metadata = Meta

        struct Meta: GranitePayload {
            let appearance: AppAppearance
        }

        func reduce(state: inout Center.State, payload: Meta) {
            state.appearance = payload.appearance
        }
    }
}
