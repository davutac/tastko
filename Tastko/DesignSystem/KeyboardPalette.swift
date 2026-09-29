import SwiftUI

// MARK: - KeyboardPalette
/// Every color the keyboard chrome and keycaps draw with, for one color scheme.
nonisolated struct KeyboardPalette: Equatable, Sendable {
    var colorScheme: ColorScheme
    var chassis: Color
    var chrome: Color
    var keyFill: Color
    var keyEdge: Color
    var keyShadow: Color
    var label: Color
    var secondaryLabel: Color
    var border: Color
    var active: Color
    var deadKey: Color
    var error: Color
    /// Draws key borders in every style, as Increase Contrast does.
    var emphasizesBorders = false

    // MARK: - Standard
    /// The asset catalog palette; its colors resolve against the environment's color scheme.
    static func standard(_ colorScheme: ColorScheme) -> Self {
        Self(
            colorScheme: colorScheme,
            chassis: Color("KeyboardChassis"),
            chrome: Color("KeyboardChrome"),
            keyFill: Color("KeyboardKeyFill"),
            keyEdge: Color("KeyboardKeyEdge"),
            keyShadow: Color("KeyboardKeyShadow"),
            label: Color("KeyboardLabel"),
            secondaryLabel: Color("KeyboardSecondaryLabel"),
            border: Color("KeyboardBorder"),
            active: Color("KeyboardActive"),
            deadKey: .orange,
            error: Color("KeyboardError")
        )
    }

    // MARK: - Imported Key Colors
    static func imported(_ components: PanelEditorColorComponents?) -> Color? {
        guard let components else { return nil }
        return Color(
            .sRGB,
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: components.alpha
        )
    }
}

// MARK: - Hex Colors
extension Color {
    nonisolated init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
