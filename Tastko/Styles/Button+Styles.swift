import SwiftUI

// MARK: - SubtleIconButtonStyle
struct SubtleIconButtonStyle: ButtonStyle {
    // MARK: - Body
    func makeBody(configuration: Configuration) -> some View {
        SubtleIconButtonContent(configuration: configuration)
    }
}

// MARK: - SubtleIconButtonContent
private struct SubtleIconButtonContent: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.keyboardPalette) private var palette
    @Environment(\.keycapCorners) private var corners
    @State private var isHovered = false

    // MARK: - Body
    var body: some View {
        configuration.label
            .foregroundStyle(palette.label)
            .frame(width: 20, height: 20)
            .background {
                KeycapShape(cornerRadius: corners.radius)
                    .fill(palette.keyFill)
                    .opacity(isEnabled && isHovered ? 1 : 0)
            }
            .opacity(configuration.isPressed ? 0.65 : 1)
            .contentShape(.rect)
            .onHover { isHovered = $0 }
    }
}

// MARK: - TitlebarButtonStyle
struct TitlebarButtonStyle: ButtonStyle {
    // MARK: - Body
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .buttonStyle(.plain)
            .frame(height: AppConstants.titlebarHeight)
            .padding(.horizontal, 8)
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// MARK: - ScaledIconButtonStyle
struct ScaledIconButtonStyle: ButtonStyle {
    let size: CGSize
    let symbolScaleFactor: CGFloat
    let minimumSymbolSize: CGFloat
    @Environment(\.keyboardPalette) private var palette

    // MARK: - Initialization
    init(
        size: CGSize,
        symbolScaleFactor: CGFloat,
        minimumSymbolSize: CGFloat = 24
    ) {
        self.size = size
        self.symbolScaleFactor = symbolScaleFactor
        self.minimumSymbolSize = minimumSymbolSize
    }

    // MARK: - Body
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size.width, height: size.height)
            .background(palette.keyFill, in: .rect(cornerRadius: cornerRadius))
            .contentShape(.rect(cornerRadius: cornerRadius))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }

    // MARK: - Metrics
    private var symbolSize: CGFloat {
        max(minimumSymbolSize, min(size.width, size.height) * symbolScaleFactor)
    }

    private var cornerRadius: CGFloat {
        max(12, min(size.width, size.height) * 0.24)
    }
}

// MARK: - ButtonStyle Extension
extension ButtonStyle where Self == TitlebarButtonStyle {
    static var titlebar: TitlebarButtonStyle {
        TitlebarButtonStyle()
    }
}

extension ButtonStyle where Self == ScaledIconButtonStyle {
    static func scaledIcon(
        size: CGSize,
        symbolScaleFactor: CGFloat,
        minimumSymbolSize: CGFloat = 24
    ) -> ScaledIconButtonStyle {
        ScaledIconButtonStyle(
            size: size,
            symbolScaleFactor: symbolScaleFactor,
            minimumSymbolSize: minimumSymbolSize
        )
    }
}
