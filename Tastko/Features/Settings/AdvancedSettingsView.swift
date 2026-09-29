import Defaults
import SwiftUI

// MARK: - Advanced Settings
@MainActor
struct AdvancedSettingsView: View {
    @Default(.experimentalLockScreenDisplay) private var experimentalLockScreenDisplay
    @Environment(\.floatingWindowController) private var floatingWindowController

    // MARK: - Body
    var body: some View {
        Form {
            SettingsPaneHeader(pane: .advanced)

            Section {
                Toggle("Show keyboard on lock screen", isOn: $experimentalLockScreenDisplay)
                    .disabled(floatingWindowController.isScreenLocked)
                LabeledContent("Status") {
                    Text(floatingWindowController.lockScreenDisplayStatus)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Lock Screen")
            } footer: {
                Text(
                    "Predictions stay off on the lock screen. Uses private macOS APIs; compatibility may change after updates."
                )
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .onChange(of: experimentalLockScreenDisplay) {
            floatingWindowController.updateLockScreenDisplay()
        }
    }
}
