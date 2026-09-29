import Defaults
import SwiftUI

// MARK: - General Settings
@MainActor
struct GeneralSettingsView: View {
    let updateService: AppUpdateService
    @Default(.floatingWindowMinimumScale) private var minimumScale
    @Default(.pointerAutoHideEnabled) private var pointerAutoHideEnabled
    @Default(.pointerAutoHideDelay) private var pointerAutoHideDelay
    @Default(.hotCornerDwellDuration) private var hotCornerDwellDuration
    @Environment(\.floatingWindowController) private var floatingWindowController

    // MARK: - Body
    var body: some View {
        Form {
            SettingsPaneHeader(pane: .general)
            LaunchAtLoginSettingsView()
            AppUpdateSettingsView(updateService: updateService)
            keyboardWindowSettings
            hotCornerSettings
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }

    // MARK: - Keyboard Window
    private var keyboardWindowSettings: some View {
        Section {
            Toggle("Hide when the pointer is idle", isOn: $pointerAutoHideEnabled)
            SettingsStepperRow(
                title: "Hide after",
                value: $pointerAutoHideDelay,
                range: PointerVisibilityPolicy.inactivityDelayRange,
                step: 5,
                valueText: Text(
                    "\(pointerAutoHideDelay, format: .number.precision(.fractionLength(0))) seconds"
                )
            )
            .disabled(!pointerAutoHideEnabled)

            SettingsStepperRow(
                title: "Minimum keyboard scale",
                value: minimumScaleBinding,
                range: minimumScaleRange,
                step: 0.05,
                valueText: Text(minimumScale, format: .percent.precision(.fractionLength(0)))
            )
        } header: {
            Text("Keyboard Window")
        } footer: {
            Text("Move the pointer to show a hidden keyboard again.")
        }
    }

    // MARK: - Hot Corner
    private var hotCornerSettings: some View {
        Section {
            SettingsStepperRow(
                title: "Dwell time",
                value: $hotCornerDwellDuration,
                range: PointerVisibilityPolicy.cornerDwellRange,
                step: 0.5,
                valueText: Text(
                    "\(hotCornerDwellDuration, format: .number.precision(.fractionLength(1))) seconds"
                )
            )
        } header: {
            Text("Hot Corner")
        } footer: {
            Text("Pause in the bottom-right corner of the screen to hide or show the keyboard.")
        }
    }

    // MARK: - Bindings
    private var minimumScaleRange: ClosedRange<Double> {
        let range = FloatingWindowDefaults.allowedMinimumKeyboardScaleRange
        return Double(range.lowerBound)...Double(range.upperBound)
    }

    private var minimumScaleBinding: Binding<Double> {
        Binding {
            minimumScale
        } set: { newValue in
            minimumScale = Double(
                CGFloat(newValue).clamped(
                    to: FloatingWindowDefaults.allowedMinimumKeyboardScaleRange
                )
            )
            floatingWindowController.updateSettings()
        }
    }
}
