import SwiftUI

// MARK: - KeyboardDesignPreview
private struct KeyboardDesignPreview: View {
    let theme: KeyboardTheme
    let colorScheme: ColorScheme

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: KeyboardDesign.Metrics.rowSpacing) {
            Text(theme.name)
                .font(KeyboardDesign.Typography.title)
            HStack(spacing: KeyboardDesign.Metrics.rowSpacing) {
                ForEach(["morning", "afternoon", "evening"], id: \.self) { word in
                    Button(word) {}
                        .buttonStyle(.keycap)
                }
            }
            ForEach(KeycapStyle.allCases) { style in
                HStack(spacing: 0) {
                    SampleKey("A")
                    SampleKey("⇧", width: 1.5, isActive: true)
                    SampleKey("´", isDeadKey: true)
                    Text(style.title)
                        .font(.caption)
                        .padding(.leading, 8)
                }
                .environment(\.keycapStyle, style)
            }
        }
        .padding(KeyboardDesign.Metrics.rowInset)
        .background(theme.palette(for: colorScheme).chassis)
        .keyboardPalette(theme.palette(for: colorScheme))
    }
}

#Preview("Tastko Light") {
    KeyboardDesignPreview(theme: .tastko, colorScheme: .light)
}

#Preview("Tastko Dark") {
    KeyboardDesignPreview(theme: .tastko, colorScheme: .dark)
}

#Preview("Tokyo Night") {
    KeyboardDesignPreview(theme: .tokyoNight, colorScheme: .dark)
}
