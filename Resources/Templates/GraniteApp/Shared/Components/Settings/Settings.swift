import Granite

struct SettingsComponent: GraniteComponent {
    @Command var center: Center
    @Relay var config: ConfigService
}
