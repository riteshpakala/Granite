import Granite

struct HomeComponent: GraniteComponent {
    @Command var center: Center

    @Relay var environment: EnvironmentService
    @Relay var config: ConfigService
}
