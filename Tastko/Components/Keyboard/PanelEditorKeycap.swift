import SwiftUI

// MARK: - PanelEditorKeycap
struct PanelEditorKeycap: View {
    let button: PanelEditorButton
    let presentation: ResolvedKey
    let scale: CGFloat
    let isPressed: Bool
    let isHovered: Bool
    let isActive: Bool
    @Environment(\.keyboardPalette) private var palette
    @Environment(\.keycapCorners) private var corners

    // MARK: - Body
    var body: some View {
        let keyShape = PanelEditorKeyShape(
            buttonShape: button.shape,
            cornerRadius: corners.radius * scale,
            frameInset: keyInset
        )

        KeycapSurface(
            shape: keyShape,
            fill: KeyboardPalette.imported(button.backgroundColor),
            isPressed: isPressed,
            isHovered: isHovered,
            isActive: isActive,
            isDeadKey: presentation.isDeadKey
        ) {
            ZStack(alignment: .topTrailing) {
                Text(displayTitle)
                    .font(KeyboardDesign.Typography.key(size: button.fontSize * scale))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .foregroundStyle(
                        KeyboardPalette.imported(button.foregroundColor) ?? palette.label
                    )
                    .padding(max(3, 4 * scale))
                    .padding(.leading, labelLeadingInset)
                    .keycapLabelInset(isPressed: isPressed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let secondaryTitle = presentation.secondaryTitle {
                    Text(secondaryTitle)
                        .font(KeyboardDesign.Typography.secondaryKey(scale: scale))
                        .lineLimit(1)
                        .foregroundStyle(
                            KeyboardPalette.imported(button.foregroundColor)
                                ?? palette.secondaryLabel
                        )
                        .padding(.top, max(2, 3 * scale))
                        .padding(.trailing, max(3, 4 * scale))
                }
            }
            .overlay(alignment: .topLeading) {
                if isActive {
                    Circle()
                        .fill(palette.active)
                        .frame(width: max(4, 4 * scale), height: max(4, 4 * scale))
                        .padding(max(4, 6 * scale))
                }
            }
        }
        .padding(keyInset)
        .scaleEffect(isPressed ? 0.97 : 1)
        .offset(y: isPressed ? max(1, scale) : 0)
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Metrics
    private var keyInset: CGFloat {
        max(1, KeyboardDesign.Metrics.keyInset * scale)
    }

    // MARK: - Label
    /// Centers an ISO Return label over its narrower lower part.
    private var labelLeadingInset: CGFloat {
        switch button.shape {
        case .rectangle: 0
        case .isoReturn:
            button.frame.width * scale * PanelEditorISOEnterMetrics.lowerLeadingInsetFraction
        }
    }

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
