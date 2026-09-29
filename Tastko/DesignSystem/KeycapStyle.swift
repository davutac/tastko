import Defaults
import SwiftUI

// MARK: - KeycapStyle
/// How a keycap's surface is drawn.
nonisolated enum KeycapStyle: String, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case mechanical
    case raised
    case flat
    case floating
    case outline
    case underline
    case glass
    case soft
    case inset
    case bold

    var id: Self { self }

    var title: String {
        switch self {
        case .mechanical: "Mechanical"
        case .raised: "Raised"
        case .flat: "Flat"
        case .floating: "Floating"
        case .outline: "Outline"
        case .underline: "Underline"
        case .glass: "Glass"
        case .soft: "Soft"
        case .inset: "Inset"
        case .bold: "Bold"
        }
    }

    /// Space at the bottom of the key taken by the skirt, which labels stay clear of.
    var labelBottomInset: CGFloat {
        self == .mechanical ? KeyboardDesign.Metrics.keySkirtHeight : 0
    }
}

// MARK: - KeycapCorners
nonisolated enum KeycapCorners: String, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case square
    case standard
    case round
    case pill

    var id: Self { self }

    var title: String {
        switch self {
        case .square: "Square"
        case .standard: "Standard"
        case .round: "Round"
        case .pill: "Pill"
        }
    }

    var radius: CGFloat {
        switch self {
        case .square: 3
        case .standard: 6
        case .round: 11
        case .pill: 999
        }
    }
}

// MARK: - KeycapShape
/// A continuous rounded rectangle whose radius never exceeds half its shorter side,
/// so pill corners become a clean capsule.
nonisolated struct KeycapShape: Shape {
    var cornerRadius: CGFloat

    // MARK: - Path
    func path(in rect: CGRect) -> Path {
        let maximumRadius = min(rect.width, rect.height) / 2
        // Continuous corners distort at the maximum radius, so capsules use circular ones.
        return Path(
            roundedRect: rect,
            cornerRadius: min(cornerRadius, maximumRadius),
            style: cornerRadius < maximumRadius ? .continuous : .circular
        )
    }
}

// MARK: - KeyboardAppearance
/// Which palette an adaptive theme uses.
nonisolated enum KeyboardAppearance: String, CaseIterable, Identifiable, Defaults.Serializable,
    Sendable
{
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
