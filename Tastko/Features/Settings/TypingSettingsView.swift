import Defaults
import SwiftUI

// MARK: - Typing Settings
@MainActor
struct TypingSettingsView: View {
    @Default(.textPredictionEnabled) private var textPredictionEnabled
    @Default(.swipeTypingEnabled) private var swipeTypingEnabled
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

            Section {
                Toggle("Type words by swiping across letters", isOn: $swipeTypingEnabled)
            } header: {
                Text("Swipe Typing")
            } footer: {
                Text(
                    """
                    Press the first letter of a word, move through its letters, and release. \
                    Other readings appear as suggestions. English and German. While this is \
                    on, letter keys type when released and don't repeat when held. The hand \
                    button on the keyboard's titlebar turns it on and off too.
                    """
                )
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
