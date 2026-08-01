import Granite
import SwiftUI

extension SettingsComponent: View {
    var view: some View {
        Form {
            Section("Application") {
                Picker("Appearance", selection: appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }

                Toggle("Show helpful tips", isOn: showsTips)
            }

            Section("Usage") {
                LabeledContent("Launches", value: config.state.launchCount.formatted())

                if let lastOpenedAt = config.state.lastOpenedAt {
                    LabeledContent("Last opened") {
                        Text(lastOpenedAt, format: .dateTime.month().day().year().hour().minute())
                    }
                }
            }

            Section {
                Button("Restore Default Settings") {
                    config.center.resetSettings.send()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private var appearance: Binding<AppAppearance> {
        Binding(
            get: { config.state.appearance },
            set: {
                config.center.setAppearance.send(
                    ConfigService.SetAppearance.Meta(appearance: $0)
                )
            }
        )
    }

    private var showsTips: Binding<Bool> {
        Binding(
            get: { config.state.showsTips },
            set: {
                config.center.setShowsTips.send(
                    ConfigService.SetShowsTips.Meta(isEnabled: $0)
                )
            }
        )
    }
}
