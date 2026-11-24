import Defaults
import SwiftUI

// MARK: - SwipeTypingToggleButton
/// Turns swipe typing on or off from the titlebar, as Settings › Typing › Swipe Typing does.
struct SwipeTypingToggleButton: View {
    @Default(.swipeTypingEnabled) private var isOn
    @Environment(\.keyboardPalette) private var palette

    // MARK: - Body
    var body: some View {
        Button(helpText, systemImage: isOn ? "hand.draw.fill" : "hand.draw") {
            isOn.toggle()
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .foregroundStyle(isOn ? palette.active : palette.secondaryLabel)
        .accessibilityLabel("Swipe typing")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("toggle-swipe-typing")
        .help(helpText)
    }

    // MARK: - Text
    private var helpText: String {
        isOn ? "Turn off swipe typing" : "Turn on swipe typing"
    }
}
