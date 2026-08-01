import Foundation
import Granite

extension ConfigService {
    struct Center: GraniteCenter {
        struct State: GraniteState {
            var appearance: AppAppearance = .system
            var showsTips = true
            var hasCompletedOnboarding = false
            var launchCount = 0
            var lastOpenedAt: Date?
        }

        @Store(
            persist: "__BUNDLE_ID__.configuration",
            autoSave: true
        ) var state: State

        @Event var recordLaunch: RecordLaunch.Reducer
        @Event var setAppearance: SetAppearance.Reducer
        @Event var setShowsTips: SetShowsTips.Reducer
        @Event var resetSettings: ResetSettings.Reducer
    }
}
