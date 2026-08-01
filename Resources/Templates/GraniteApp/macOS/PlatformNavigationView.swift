import SwiftUI

struct PlatformNavigationView: View {
    @Binding var selection: AppDestination

    var body: some View {
        NavigationSplitView {
            List(AppDestination.allCases, selection: optionalSelection) { destination in
                Label(destination.title, systemImage: destination.symbol)
                    .tag(destination)
            }
            .navigationTitle("__DISPLAY_NAME__")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            destinationView
        }
        .frame(minWidth: 760, minHeight: 520)
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
