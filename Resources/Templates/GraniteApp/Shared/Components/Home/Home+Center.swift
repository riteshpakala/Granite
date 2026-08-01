import Granite

extension HomeComponent {
    struct Center: GraniteCenter {
        struct State: GraniteState {
            var selectedDestination: AppDestination = .home
        }

        @Store var state: State
    }
}
