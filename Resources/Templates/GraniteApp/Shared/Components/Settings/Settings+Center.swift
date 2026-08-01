import Granite

extension SettingsComponent {
    struct Center: GraniteCenter {
        struct State: GraniteState {}

        @Store var state: State
    }
}
