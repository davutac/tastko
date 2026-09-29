import Defaults
import SwiftUI

// MARK: - Typing Settings
@MainActor
struct TypingSettingsView: View {
    @Default(.textPredictionEnabled) private var textPredictionEnabled
    @Environment(\.floatingWindowController) private var floatingWindowController
    @Environment(\.textPredictionService) private var textPredictionService

    // MARK: - Body
    var body: some View {
        Form {
            SettingsPaneHeader(pane: .typing)

            Section {
                Toggle("Suggest words while typing", isOn: $textPredictionEnabled)
                LabeledContent("Prediction model") {
                    Text(textPredictionService.modelStatus)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Predictions")
            } footer: {
                Text("Suggestions appear above the keyboard; click one to insert it.")
            }

            ButtonSoundSettingsView()
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .onChange(of: textPredictionEnabled) {
            floatingWindowController.updatePredictionLifecycle()
        }
    }
}
