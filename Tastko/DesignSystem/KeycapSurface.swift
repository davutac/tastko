import SwiftUI

// MARK: - KeycapSurface
struct KeycapSurface<KeyShape: Shape>: View {
    let shape: KeyShape
    var fill: Color = KeyboardDesign.Palette.keyFill
    var isPressed = false
    var isHovered = false
    var isActive = false
    var isDeadKey = false
    @Environment(\.colorSchemeContrast) private var contrast

    // MARK: - Body
    var body: some View {
        shape
            .fill(fill)
            .overlay {
                if isPressed { shape.fill(KeyboardDesign.Palette.active.opacity(0.25)) }
            }
            .opacity(isHovered ? 0.86 : 1)
            .overlay {
                shape.stroke(borderColor, lineWidth: borderWidth)
            }
            .transaction { $0.animation = nil }
            .allowsHitTesting(false)
    }

    // MARK: - Interaction
    private var borderColor: Color {
        if isActive || isPressed { return KeyboardDesign.Palette.active }
        if isDeadKey { return KeyboardDesign.Palette.deadKey }
        if isHovered { return KeyboardDesign.Palette.label.opacity(0.28) }
        return KeyboardDesign.Palette.border
    }

    private var borderWidth: CGFloat {
        contrast == .increased || isActive || isPressed || isDeadKey ? 2 : 1
    }
}
