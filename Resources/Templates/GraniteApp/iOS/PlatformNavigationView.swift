import SwiftUI

struct PlatformNavigationView: View {
    @Binding var selection: AppDestination
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .compact {
            tabNavigation
        } else {
            sidebarNavigation
        }
    }

    private var tabNavigation: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeContentView()
                    .navigationTitle(AppDestination.home.title)
            }
            .tabItem {
                Label(AppDestination.home.title, systemImage: AppDestination.home.symbol)
            }
            .tag(AppDestination.home)

            NavigationStack {
                SettingsComponent()
            }
            .tabItem {
                Label(AppDestination.settings.title, systemImage: AppDestination.settings.symbol)
            }
            .tag(AppDestination.settings)
        }
    }

    private var sidebarNavigation: some View {
        NavigationSplitView {
            List(AppDestination.allCases, selection: optionalSelection) { destination in
                Label(destination.title, systemImage: destination.symbol)
                    .tag(destination)
            }
            .navigationTitle("__DISPLAY_NAME__")
        } detail: {
            destinationView
        }
    }

    private var optionalSelection: Binding<AppDestination?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue {
                    selection = newValue
                }
            }
        )
    }

    @ViewBuilder
    private var destinationView: some View {
        switch selection {
        case .home:
            HomeContentView()
                .navigationTitle(AppDestination.home.title)
        case .settings:
            SettingsComponent()
        }
    }
}
