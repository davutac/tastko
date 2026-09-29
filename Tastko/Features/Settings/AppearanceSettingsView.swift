import Defaults
import SwiftUI

// MARK: - AppearanceSettingsView
struct AppearanceSettingsView: View {
    @Default(.keyboardTheme) private var themeID
    @Default(.keyboardAppearance) private var appearance
    @Default(.keycapStyle) private var keycapStyle
    @Default(.keycapCorners) private var keycapCorners

    // MARK: - Body
    var body: some View {
        Form {
            SettingsPaneHeader(pane: .appearance)

            Section {
                KeyboardSettingsPreview()
                    .keyboardTheme()
            }

            themeSettings
            keySettings
        }
        .formStyle(.grouped)
    }

    // MARK: - Theme
    private var themeSettings: some View {
        Section("Theme") {
            let current = selectedTheme
            ForEach(KeyboardTheme.Group.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: columns(4), spacing: 12) {
                        ForEach(KeyboardTheme.all.filter { $0.group == group }) { theme in
                            themeCard(theme, isSelected: theme.id == current.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Picker("Appearance", selection: $appearance) {
                ForEach(KeyboardAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!current.isAdaptive)

            if !current.isAdaptive {
                Text(
                    "\(current.name) only comes in \(current.appearanceDescription.lowercased())."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Theme Card
    private func themeCard(_ theme: KeyboardTheme, isSelected: Bool) -> some View {
        AppearanceOptionCard(
            title: theme.name,
            subtitle: theme.appearanceDescription,
            isSelected: isSelected
        ) {
            themeID = theme.id
        } preview: {
            ThemeSwatch(theme: theme)
                .keyboardTheme()
        }
    }

    // MARK: - Keys
    private var keySettings: some View {
        Section("Keys") {
            LazyVGrid(columns: columns(5), spacing: 12) {
                ForEach(KeycapStyle.allCases) { style in
                    AppearanceOptionCard(
                        title: style.title,
                        isSelected: style == keycapStyle
                    ) {
                        keycapStyle = style
                    } preview: {
                        SwatchKeys(unit: 42, fontSize: 15)
                            .environment(\.keycapStyle, style)
                            .keyboardTheme()
                    }
                }
            }
            .padding(.vertical, 4)

            Picker("Corners", selection: $keycapCorners) {
                ForEach(KeycapCorners.allCases) { corners in
                    Text(corners.title).tag(corners)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Resolution
    private var selectedTheme: KeyboardTheme {
        KeyboardTheme.named(themeID)
    }

    private func columns(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }
}

#Preview {
    AppearanceSettingsView()
        .frame(width: 680, height: 640)
}
