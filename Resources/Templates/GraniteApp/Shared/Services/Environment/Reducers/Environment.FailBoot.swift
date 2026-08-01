import Granite

extension EnvironmentService {
    struct FailBoot: GraniteReducer {
        typealias Center = EnvironmentService.Center
        typealias Metadata = Meta

        struct Meta: GranitePayload {
            let message: String
        }

        func reduce(state: inout Center.State, payload: Meta) {
            state.phase = .failed
            state.lastError = payload.message
        }
    }
}
