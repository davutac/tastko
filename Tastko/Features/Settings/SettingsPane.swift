import SwiftUI

// MARK: - SettingsPane
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case appearance
    case typing
    case ai
    case advanced
    #if DEBUG
        case debug
    #endif

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .typing: "Typing"
        case .ai: "AI"
        case .advanced: "Advanced"
        #if DEBUG
            case .debug: "Debug"
        #endif
        }
    }

    var summary: String {
        switch self {
        case .general: "Startup, updates, and how the keyboard window behaves."
        case .appearance: "Themes, key styles, and corner shapes for the keyboard."
        case .typing: "Word predictions and the sound each key makes."
        case .ai: "Providers and the prompt used for sentence completions."
        case .advanced: "Experimental features that rely on private macOS behavior."
        #if DEBUG
            case .debug: "Try sentence completions against the active provider."
        #endif
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintpalette.fill"
        case .typing: "keyboard.fill"
        case .ai: "sparkles"
        case .advanced: "flask.fill"
        #if DEBUG
            case .debug: "ladybug.fill"
        #endif
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .appearance: .blue
        case .typing: .green
        case .ai: .purple
        case .advanced: .orange
        #if DEBUG
            case .debug: .red
        #endif
        }
    }
}

// MARK: - SettingsPaneIcon
/// A System Settings–style icon: a white symbol on a rounded, colored square.
struct SettingsPaneIcon: View {
    let pane: SettingsPane
    var size: CGFloat = 22

    // MARK: - Body
    var body: some View {
        Image(systemName: pane.systemImage)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(pane.tint, in: .rect(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - SettingsPaneHeader
/// The card at the top of each pane that names it and says what it covers.
struct SettingsPaneHeader: View {
    let pane: SettingsPane

    // MARK: - Body
    var body: some View {
        Section {
            HStack(spacing: 14) {
                SettingsPaneIcon(pane: pane, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pane.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(pane.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }
}
