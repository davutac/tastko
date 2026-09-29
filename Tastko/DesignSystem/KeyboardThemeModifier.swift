import Defaults
import SwiftUI

// MARK: - KeyboardThemeModifier
/// Resolves the saved theme, appearance, and keycap settings into the environment.
/// Apply once at the root of every window that draws keyboard UI.
private struct KeyboardThemeModifier: ViewModifier {
    @Default(.keyboardTheme) private var themeID
    @Default(.keyboardAppearance) private var appearance
    @Default(.keycapStyle) private var keycapStyle
    @Default(.keycapCorners) private var keycapCorners
    @Environment(\.colorScheme) private var systemColorScheme

    // MARK: - Body
    func body(content: Content) -> some View {
        content
            .keyboardPalette(
                KeyboardTheme.named(themeID)
                    .palette(for: appearance.colorScheme ?? systemColorScheme)
            )
            .environment(\.keycapStyle, keycapStyle)
            .environment(\.keycapCorners, keycapCorners)
    }
}

// MARK: - View Extension
extension View {
    // MARK: - Saved Theme
    func keyboardTheme() -> some View {
        modifier(KeyboardThemeModifier())
    }

    // MARK: - Explicit Palette
    /// Draws the content with `palette`, matching system controls to its color scheme.
    func keyboardPalette(_ palette: KeyboardPalette) -> some View {
        foregroundStyle(palette.label)
            .environment(\.keyboardPalette, palette)
            .environment(\.colorScheme, palette.colorScheme)
    }
}
