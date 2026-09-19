import SwiftUI

// MARK: - PanelEditorKeycap
struct PanelEditorKeycap: View {
    let button: PanelEditorButton
    let presentation: ResolvedKeyPresentation
    let scale: CGFloat
    let isPressed: Bool
    let isHovered: Bool
    let isActive: Bool

    // MARK: - Body
    var body: some View {
        let keyShape = PanelEditorKeyShape(
            buttonShape: button.shape,
            cornerRadius: KeyboardDesign.Metrics.keyRadius * scale
        )

        ZStack(alignment: .topTrailing) {
            KeycapSurface(
                shape: keyShape,
                fill: KeyboardDesign.Palette.imported(
                    button.backgroundColor,
                    fallback: KeyboardDesign.Palette.keyFill
                ),
                isPressed: isPressed,
                isHovered: isHovered,
                isActive: isActive,
                isDeadKey: presentation.isDeadKey
            )

            Text(displayTitle)
                .font(KeyboardDesign.Typography.key(size: button.fontSize * scale))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .foregroundStyle(
                    KeyboardDesign.Palette.imported(
                        button.foregroundColor,
                        fallback: KeyboardDesign.Palette.label
                    )
                )
                .padding(max(3, 4 * scale))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let secondaryTitle = presentation.secondaryTitle {
                Text(secondaryTitle)
                    .font(KeyboardDesign.Typography.secondaryKey(scale: scale))
                    .lineLimit(1)
                    .foregroundStyle(
                        KeyboardDesign.Palette.imported(
                            button.foregroundColor,
                            fallback: KeyboardDesign.Palette.secondaryLabel
                        )
                    )
                    .padding(.top, max(1, 2 * scale))
                    .padding(.trailing, max(2, 3 * scale))
            }
        }
        .overlay(alignment: .topLeading) {
            if isActive {
                Circle()
                    .fill(KeyboardDesign.Palette.active)
                    .frame(width: max(4, 4 * scale), height: max(4, 4 * scale))
                    .padding(max(4, 6 * scale))
            }
        }
        .padding(max(1, KeyboardDesign.Metrics.keyInset * scale))
        .scaleEffect(isPressed ? 0.97 : 1)
        .offset(y: isPressed ? max(1, scale) : 0)
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Label
    private var displayTitle: String {
        switch presentation.title {
        case "ISO Section": "§"
        case "Page Up": "pg up"
        case "Page Down": "pg dn"
        case "Space": "space"
        default: presentation.title
        }
    }
}
