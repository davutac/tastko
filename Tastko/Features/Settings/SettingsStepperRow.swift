import SwiftUI

// MARK: - SettingsStepperRow
/// A settings row with its label on the leading edge and the value beside the stepper.
struct SettingsStepperRow<Value: Strideable>: View {
    let title: String
    @Binding var value: Value
    let range: ClosedRange<Value>
    let step: Value.Stride
    let valueText: Text

    // MARK: - Body
    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                valueText
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper(title, value: $value, in: range, step: step)
                    .labelsHidden()
                    .accessibilityValue(valueText)
            }
        }
    }
}
