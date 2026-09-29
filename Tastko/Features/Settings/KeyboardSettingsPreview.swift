import SwiftUI

// MARK: - KeyboardSettingsPreview
/// A small pressable keyboard drawn with the current palette and keycap settings.
struct KeyboardSettingsPreview: View {
    @Environment(\.keyboardPalette) private var palette

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SampleKey("esc", width: 1.5)
                ForEach(["Q", "W", "E", "R", "T", "Y"], id: \.self) { SampleKey($0) }
                SampleKey("delete", width: 1.5)
            }
            HStack(spacing: 0) {
                SampleKey("⇧", width: 2, isActive: true)
                ForEach(["A", "S", "D", "F"], id: \.self) { SampleKey($0) }
                SampleKey("´", isDeadKey: true)
                SampleKey("return", width: 2)
            }
            HStack(spacing: 0) {
                SampleKey("fn", width: 1.5)
                SampleKey("space", width: 6)
                SampleKey("⌘", width: 1.5)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(palette.chassis, in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Keyboard preview")
    }
}

// MARK: - ThemeSwatch
/// A theme's chassis and keys; adaptive themes show their light and dark palettes side by side.
struct ThemeSwatch: View {
    let theme: KeyboardTheme

    // MARK: - Body
    var body: some View {
        HStack(spacing: 0) {
            if let light = theme.light {
                half(light)
            }
            if let dark = theme.dark {
                half(dark)
            }
        }
    }

    // MARK: - Palette Half
    private func half(_ palette: KeyboardPalette) -> some View {
        SwatchKeys(unit: 28, fontSize: 12)
            .keyboardPalette(palette)
    }
}

// MARK: - SwatchKeys
/// A plain and a latched key on the palette's chassis, filling the swatch.
struct SwatchKeys: View {
    let unit: CGFloat
    let fontSize: CGFloat
    @Environment(\.keyboardPalette) private var palette

    // MARK: - Body
    var body: some View {
        HStack(spacing: 0) {
            SampleKey("A", unit: unit, fontSize: fontSize)
            SampleKey("⇧", unit: unit, fontSize: fontSize, isActive: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.chassis)
    }
}

// MARK: - SampleKey
/// A single preview key that shows hover and press states like a real keycap.
struct SampleKey: View {
    let title: String
    let width: CGFloat
    let unit: CGFloat
    let fontSize: CGFloat
    let isActive: Bool
    let isDeadKey: Bool
    @Environment(\.keyboardPalette) private var palette
    @Environment(\.keycapCorners) private var corners
    @GestureState private var isPressed = false
    @State private var isHovered = false

    init(
        _ title: String,
        width: CGFloat = 1,
        unit: CGFloat = 46,
        fontSize: CGFloat = 16,
        isActive: Bool = false,
        isDeadKey: Bool = false
    ) {
        self.title = title
        self.width = width
        self.unit = unit
        self.fontSize = fontSize
        self.isActive = isActive
        self.isDeadKey = isDeadKey
    }

    // MARK: - Body
    var body: some View {
        KeycapSurface(
            shape: KeycapShape(cornerRadius: corners.radius),
            isPressed: isPressed,
            isHovered: isHovered,
            isActive: isActive,
            isDeadKey: isDeadKey
        ) {
            Text(title)
                .font(.system(size: fontSize))
                .foregroundStyle(palette.label)
                .keycapLabelInset(isPressed: isPressed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(KeyboardDesign.Metrics.keyInset)
        .scaleEffect(isPressed ? 0.97 : 1)
        .offset(y: isPressed ? 1 : 0)
        .frame(width: unit * width, height: unit)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, isPressed, _ in isPressed = true }
        )
        .transaction { $0.animation = nil }
    }
}
