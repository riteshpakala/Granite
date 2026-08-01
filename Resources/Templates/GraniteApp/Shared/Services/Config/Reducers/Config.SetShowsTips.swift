import Granite

extension ConfigService {
    struct SetShowsTips: GraniteReducer {
        typealias Center = ConfigService.Center
        typealias Metadata = Meta

        struct Meta: GranitePayload {
            let isEnabled: Bool
        }

        func reduce(state: inout Center.State, payload: Meta) {
            state.showsTips = payload.isEnabled
        }
    }
}
