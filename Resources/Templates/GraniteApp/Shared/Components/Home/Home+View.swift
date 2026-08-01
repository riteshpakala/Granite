import Granite
import SwiftUI

extension HomeComponent: View {
    var view: some View {
        Group {
            switch environment.state.phase {
            case .idle:
                AppLoadingView()
            case .ready:
                PlatformNavigationView(selection: destination)
            case .failed:
                AppEmptyStateView(
                    symbol: "exclamationmark.triangle",
                    title: "Couldn’t start __DISPLAY_NAME__",
                    message: environment.state.lastError ?? "An unknown startup error occurred.",
                    actionTitle: "Try Again",
                    action: retryBoot
                )
            }
        }
        .preferredColorScheme(config.state.appearance.colorScheme)
        .task(id: config.isLoaded) {
            guard config.isLoaded else { return }
            boot()
        }
    }

    private var destination: Binding<AppDestination> {
        center.$state.binding.selectedDestination
    }

    private func boot() {
        guard environment.state.phase == .idle else {
            return
        }

        let isFirstLaunch = config.state.launchCount == 0
        config.center.recordLaunch.send()
        environment.center.boot.send(
            EnvironmentService.Boot.Meta(isFirstLaunch: isFirstLaunch)
        )
    }

    private func retryBoot() {
        guard environment.state.phase == .failed else { return }

        environment.center.boot.send(
            EnvironmentService.Boot.Meta(isFirstLaunch: environment.state.isFirstLaunch)
        )
    }
}
