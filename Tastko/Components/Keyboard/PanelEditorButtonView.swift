import SwiftUI

// MARK: - PanelEditorButtonView
struct PanelEditorButtonView: View {
    @Environment(\.keyInputController) private var input
    @Environment(\.keyboardService) private var keyboardService

    let button: PanelEditorButton
    let scale: CGFloat

    @State private var pressedButton: KeyMouseButton?
    @State private var isHovered = false

    // MARK: - Body
    var body: some View {
        let key = input.resolve(button)
        let isEngaged = input.isEngaged(button)

        ZStack {
            PanelEditorKeycap(
                button: button,
                presentation: key,
                scale: scale,
                isPressed: isPressed,
                isHovered: isHovered,
                isActive: isEngaged
            )

            KeyMouseEventView(
                pressedButton: $pressedButton,
                hitRegion: hitRegion,
                mousePressed: { input.press(button, with: $0.actionTrigger) },
                mouseReleasedInside: { _ in input.release(button) },
                mouseCancelled: { input.release(button) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
        }
        .contentShape(PanelEditorKeyShape(buttonShape: button.shape))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: key))
        .accessibilityValue(isPressed ? "Pressed" : "")
        .accessibilityAddTraits(isEngaged ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(accessibilityHint(for: key))
        .accessibilityAction { input.activate(button, with: .leftClick) }
        .accessibilityAction(
            named: keyboardService.isCapsLockEnabled ? "Lowercase key" : "Shifted key"
        ) {
            input.activate(button, with: .rightClick)
        }
        .onDisappear { input.release(button) }
        .onChange(of: keyboardService.inputSession) {
            input.release(button)
            pressedButton = nil
        }
    }

    // MARK: - State
    private var isPressed: Bool {
        pressedButton != nil
            || keyboardService.physicalKeyboard.snapshot.isPressed(button.primaryAction)
    }

    private var hitRegion: KeyMouseHitRegion {
        switch button.shape {
        case .rectangle: .rectangle
        case .isoReturn: .isoReturn
        }
    }

    // MARK: - Accessibility
    private func accessibilityLabel(for key: ResolvedKey) -> String {
        let title = key.title.isEmpty ? "Unavailable panel button" : key.title
        return key.isDeadKey ? "\(title), accent dead key" : title
    }

    private func accessibilityHint(for key: ResolvedKey) -> String {
        if key.isDeadKey {
            return "Combines an accent with the next character"
        }
        switch button.primaryAction {
        case .toggleFunctionToolbar:
            return "Shows or hides the system controls and function keys"
        case .keyStroke(let stroke) where stroke.key == .capsLock:
            return "Toggles system Caps Lock; right-click a letter to type lowercase"
        case .modifier(.function):
            return "Click to hold Fn; click again to release"
        case .modifier:
            return "Toggles this modifier for the next key; multiple modifiers can be combined"
        default:
            return keyboardService.isCapsLockEnabled
                ? "Left-click types uppercase; right-click types a letter in lowercase"
                : "Left-click types the key; right-click types it with Shift"
        }
    }
}
