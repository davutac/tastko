import SwiftUI

// MARK: - KeycapButtonStyle
struct KeycapButtonStyle: ButtonStyle {
    var scale: CGFloat = 1
    var fillsWidth = false
    var isExternallyPressed = false

    // MARK: - Body
    func makeBody(configuration: Configuration) -> some View {
        KeycapButtonContent(
            configuration: configuration,
            scale: scale,
            fillsWidth: fillsWidth,
            isExternallyPressed: isExternallyPressed
        )
    }
}

// MARK: - ButtonStyle Extension
extension ButtonStyle where Self == KeycapButtonStyle {
    static var keycap: KeycapButtonStyle {
        KeycapButtonStyle()
    }

    // MARK: - Configured Keycap Style
    static func keycap(
        scale: CGFloat = 1,
        fillsWidth: Bool = false,
        isExternallyPressed: Bool = false
    ) -> KeycapButtonStyle {
        KeycapButtonStyle(
            scale: scale,
            fillsWidth: fillsWidth,
            isExternallyPressed: isExternallyPressed
        )
    }
}

// MARK: - KeycapButtonContent
private struct KeycapButtonContent: View {
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat
    let fillsWidth: Bool
    let isExternallyPressed: Bool
    @Environment(\.keyboardPalette) private var palette
    @Environment(\.keycapCorners) private var corners
    @State private var isHovered = false

    // MARK: - Interaction
    private var isPressed: Bool { configuration.isPressed || isExternallyPressed }

    // MARK: - Body
    var body: some View {
        KeycapSurface(
            shape: KeycapShape(cornerRadius: corners.radius * scale),
            isPressed: isPressed,
            isHovered: isHovered
        ) {
            configuration.label
                .font(.system(size: 15 * scale, weight: .medium))
                .foregroundStyle(palette.label)
                .keycapLabelInset(isPressed: isPressed)
                .padding(.horizontal, fillsWidth ? 0 : KeyboardDesign.Metrics.suggestionInset)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .frame(height: KeyboardDesign.Metrics.suggestionHeight * scale)
        }
        .scaleEffect(isPressed ? 0.97 : 1)
        .transaction { $0.animation = nil }
        .contentShape(.rect)
        .onHover { isHovered = $0 }
    }
}
