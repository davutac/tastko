import SwiftUI

// MARK: - KeycapSurface
/// Draws a keycap and its content using the environment's style and palette.
/// `fill` overrides the palette's key color, for keys that bring their own.
struct KeycapSurface<KeyShape: Shape, Content: View>: View {
    let shape: KeyShape
    var fill: Color?
    var isPressed = false
    var isHovered = false
    var isActive = false
    var isDeadKey = false
    @ViewBuilder var content: Content
    @Environment(\.keyboardPalette) private var palette
    @Environment(\.keycapStyle) private var style
    @Environment(\.colorSchemeContrast) private var contrast

    // MARK: - Body
    var body: some View {
        content
            .background {
                surface.allowsHitTesting(false)
            }
            // Keep labels inside the glass so its shared backdrop does not blur them.
            .glassEffect(style == .glass ? .regular.tint(glassTint) : .identity, in: shape)
            .overlay {
                if let borderColor {
                    shape.stroke(borderColor, lineWidth: borderWidth)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: - Styles
    @ViewBuilder
    private var surface: some View {
        switch style {
        case .mechanical: mechanical
        case .raised: raised
        case .flat: face(keyFill)
        case .floating: floating
        case .outline: outline
        case .underline: underline
        case .glass:
            // Native glass desaturates in the nonactivating keyboard panel.
            if let fill { face(fill.opacity(0.65)) }
        case .soft: soft
        case .inset: inset
        case .bold: face(keyFill)
        }
    }

    /// A darker skirt with a drop edge, topped by an inset face that sinks when pressed.
    private var mechanical: some View {
        ZStack {
            if !isPressed {
                shape
                    .fill(palette.keyEdge)
                    .offset(y: KeyboardDesign.Metrics.keySkirtHeight)
            }

            shape.fill(keyFill.mix(with: .black, by: palette.colorScheme == .dark ? 0.25 : 0.12))

            face(keyFill)
                .padding(.horizontal, KeyboardDesign.Metrics.keyFaceInset)
                .padding(.top, KeyboardDesign.Metrics.keyFaceInset / 2)
                .padding(
                    .bottom,
                    KeyboardDesign.Metrics.keyFaceInset / 2
                        + (isPressed ? 0 : KeyboardDesign.Metrics.keySkirtHeight)
                )
        }
    }

    // Shadows are shape styles on the fill rather than `.shadow` modifiers, so dozens of
    // keys don't each render an offscreen blur layer.

    /// A face with a thin drop edge and soft shadow.
    private var raised: some View {
        face(keyFill).background {
            if !isPressed {
                shape
                    .fill(
                        palette.keyEdge.shadow(.drop(color: palette.keyShadow, radius: 1.5, y: 1))
                    )
                    .offset(y: 1)
            }
        }
    }

    /// A face lifted off the chassis by a diffused shadow.
    private var floating: some View {
        face(
            keyFill.shadow(
                .drop(
                    color: palette.keyShadow,
                    radius: isPressed ? 1 : 5,
                    y: isPressed ? 0 : 3
                )
            )
        )
    }

    /// A transparent key defined by its border; keys with their own color stay filled.
    private var outline: some View {
        face(fill ?? .clear)
    }

    /// A face with a bar along its bottom edge that carries the key's state color.
    private var underline: some View {
        face(keyFill)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(accentColor ?? palette.label.opacity(0.14))
                    .frame(height: accentColor == nil ? 2 : 3)
            }
            .clipShape(shape)
    }

    /// A face lit from the top left, with a highlight and a shadow on opposite sides.
    private var soft: some View {
        face(
            keyFill
                .shadow(
                    .drop(
                        color: isPressed ? .clear : highlightColor,
                        radius: 2.5,
                        x: -1.5,
                        y: -1.5
                    )
                )
                .shadow(
                    .drop(
                        color: palette.keyShadow,
                        radius: isPressed ? 1 : 3,
                        x: isPressed ? 0.5 : 1.5,
                        y: isPressed ? 0.5 : 2
                    )
                )
        )
    }

    /// A face carved into the chassis by an inner shadow that deepens when pressed.
    private var inset: some View {
        face(
            keyFill.shadow(
                .inner(
                    color: palette.keyEdge,
                    radius: isPressed ? 3 : 1.5,
                    y: isPressed ? 2 : 1
                )
            )
        )
    }

    /// The key shape filled with `style`, with the hover, press, or latch tint on top.
    private func face(_ style: some ShapeStyle) -> some View {
        shape
            .fill(style)
            .overlay {
                if let tint { shape.fill(tint) }
            }
    }

    // MARK: - Colors
    private var keyFill: Color { fill ?? palette.keyFill }

    private var glassTint: Color? {
        guard let fill else { return tint }
        if isPressed { return fill.mix(with: palette.active, by: 0.18) }
        if isHovered { return fill.mix(with: palette.label, by: 0.06) }
        return fill
    }

    private var highlightColor: Color {
        .white.opacity(palette.colorScheme == .dark ? 0.06 : 0.9)
    }

    private var emphasizesBorders: Bool {
        contrast == .increased || palette.emphasizesBorders
    }

    private var tint: Color? {
        if isPressed { return palette.active.opacity(0.28) }
        // Keys with their own color keep it while latched; the border marks them instead.
        if isActive, fill == nil { return palette.active.opacity(0.16) }
        if isHovered { return palette.label.opacity(0.06) }
        return nil
    }

    private var accentColor: Color? {
        if isActive || isPressed { return palette.active }
        if isDeadKey { return palette.deadKey }
        return nil
    }

    private var borderColor: Color? {
        if style == .underline { return emphasizesBorders ? palette.label.opacity(0.55) : nil }
        if let accentColor { return accentColor }
        if emphasizesBorders { return palette.label.opacity(0.55) }
        switch style {
        case .raised: return palette.border
        case .outline: return palette.label.opacity(isHovered ? 0.4 : 0.24)
        case .bold: return palette.label.opacity(isHovered ? 0.85 : 0.6)
        case .glass: return palette.label.opacity(0.08)
        default: return nil
        }
    }

    private var borderWidth: CGFloat {
        if style == .bold { return accentColor == nil ? 2 : 3 }
        if emphasizesBorders || isDeadKey { return 2 }
        return accentColor == nil ? 1 : 1.5
    }
}

// MARK: - Keycap Label Inset
extension View {
    /// Keeps a keycap's label on its face, clear of any skirt the current style draws.
    func keycapLabelInset(isPressed: Bool) -> some View {
        modifier(KeycapLabelInset(isPressed: isPressed))
    }
}

// MARK: - KeycapLabelInset
private struct KeycapLabelInset: ViewModifier {
    let isPressed: Bool
    @Environment(\.keycapStyle) private var style

    // MARK: - Body
    func body(content: Content) -> some View {
        content.padding(.bottom, isPressed ? 0 : style.labelBottomInset)
    }
}
