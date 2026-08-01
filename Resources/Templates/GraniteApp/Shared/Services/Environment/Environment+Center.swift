import Foundation
import Granite

extension EnvironmentService {
    struct Center: GraniteCenter {
        struct State: GraniteState {
            enum Phase: String, Codable, Sendable {
                case idle
                case ready
                case failed
            }

            var phase: Phase = .idle
            var startedAt: Date?
            var isFirstLaunch = false
            var lastError: String?
        }

        @Store var state: State

        @Event var boot: Boot.Reducer
        @Event var failBoot: FailBoot.Reducer
    }
}
