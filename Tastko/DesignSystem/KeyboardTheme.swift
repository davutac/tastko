import SwiftUI

// MARK: - KeyboardTheme
/// A named set of palettes. A theme with both a light and a dark palette follows the
/// keyboard appearance setting; a theme with only one always uses it.
nonisolated struct KeyboardTheme: Identifiable, Sendable {
    let id: String
    let name: String
    let light: KeyboardPalette?
    let dark: KeyboardPalette?
    var group = Group.tastko

    // MARK: - Group
    nonisolated enum Group: CaseIterable, Sendable {
        case tastko
        case community

        var title: String {
            switch self {
            case .tastko: "Tastko"
            case .community: "Community"
            }
        }
    }

    // MARK: - Resolution
    var isAdaptive: Bool { light != nil && dark != nil }

    func palette(for colorScheme: ColorScheme) -> KeyboardPalette {
        switch colorScheme {
        case .dark: dark ?? light ?? .standard(.dark)
        default: light ?? dark ?? .standard(.light)
        }
    }

    // MARK: - Description
    var appearanceDescription: String {
        if isAdaptive { return "Light & Dark" }
        return dark != nil ? "Dark" : "Light"
    }

    // MARK: - Lookup
    static func named(_ id: String) -> Self {
        all.first { $0.id == id } ?? .tastko
    }
}

// MARK: - Catalog
extension KeyboardTheme {
    static let all: [Self] = [
        .tastko, .graphite, .midnight, .oled, .paper, .highContrast,
        .tokyoNight, .tokyoNightStorm, .catppuccin, .dracula, .nord, .gruvbox,
        .solarized, .rosePine, .oneDark, .everforest, .kanagawa, .github,
    ]

    static let defaultID = tastko.id

    static let tastko = Self(
        id: "tastko",
        name: "Tastko",
        light: .standard(.light),
        dark: .standard(.dark)
    )

    static let graphite = Self(
        id: "graphite",
        name: "Graphite",
        light: nil,
        dark: .darkTheme(
            chassis: 0x121214, chrome: 0x18181A, keyFill: 0x2C2C2F,
            label: 0xF2F2F4, secondaryLabel: 0xA8A8AE,
            active: 0x79DFA4, deadKey: 0xFF9F0A, error: 0xF57575
        )
    )

    static let midnight = Self(
        id: "midnight",
        name: "Midnight",
        light: nil,
        dark: .darkTheme(
            chassis: 0x0E1014, chrome: 0x14171C, keyFill: 0x252931,
            label: 0xEEF0F4, secondaryLabel: 0xA2A8B3,
            active: 0x6CB6FF, deadKey: 0xFFA657, error: 0xFF7B72
        )
    )

    static let oled = Self(
        id: "oled",
        name: "OLED Black",
        light: nil,
        dark: .darkTheme(
            chassis: 0x000000, chrome: 0x0A0A0A, keyFill: 0x1C1C1E,
            label: 0xFFFFFF, secondaryLabel: 0x9A9A9F,
            active: 0x79DFA4, deadKey: 0xFF9F0A, error: 0xFF6961
        )
    )

    static let tokyoNight = Self(
        id: "tokyo-night",
        name: "Tokyo Night",
        light: .lightTheme(
            chassis: 0xD0D5E3, chrome: 0xE1E2E7, keyFill: 0xF4F5F9,
            label: 0x3760BF, secondaryLabel: 0x6172B0, ink: 0x848CB5,
            active: 0x2E7DE9, deadKey: 0xB15C00, error: 0xF52A65
        ),
        dark: .darkTheme(
            chassis: 0x16161E, chrome: 0x1A1B26, keyFill: 0x292E42,
            label: 0xC0CAF5, secondaryLabel: 0xA9B1D6, border: 0x414868,
            active: 0x7AA2F7, deadKey: 0xFF9E64, error: 0xF7768E
        ),
        group: .community
    )

    static let tokyoNightStorm = Self(
        id: "tokyo-night-storm",
        name: "Tokyo Night Storm",
        light: nil,
        dark: .darkTheme(
            chassis: 0x1F2335, chrome: 0x24283B, keyFill: 0x343A55,
            label: 0xC0CAF5, secondaryLabel: 0xA9B1D6, border: 0x545C7E,
            active: 0x7AA2F7, deadKey: 0xFF9E64, error: 0xF7768E
        ),
        group: .community
    )

    static let catppuccin = Self(
        id: "catppuccin",
        name: "Catppuccin",
        light: .lightTheme(
            chassis: 0xDCE0E8, chrome: 0xE6E9EF, keyFill: 0xEFF1F5,
            label: 0x4C4F69, secondaryLabel: 0x6C6F85, ink: 0x9CA0B0,
            active: 0x8839EF, deadKey: 0xFE640B, error: 0xD20F39
        ),
        dark: .darkTheme(
            chassis: 0x11111B, chrome: 0x181825, keyFill: 0x313244,
            label: 0xCDD6F4, secondaryLabel: 0xA6ADC8, border: 0x45475A,
            active: 0xCBA6F7, deadKey: 0xFAB387, error: 0xF38BA8
        ),
        group: .community
    )

    static let paper = Self(
        id: "paper",
        name: "Paper",
        light: .lightTheme(
            chassis: 0xE4E1D8, chrome: 0xECE9E1, keyFill: 0xFBFAF6,
            label: 0x2B2A26, secondaryLabel: 0x6F6B62, ink: 0x8A8475,
            active: 0x2F7D4F, deadKey: 0xC46A00, error: 0xB3261E
        ),
        dark: nil
    )

    static let highContrast = Self(
        id: "high-contrast",
        name: "High Contrast",
        light: KeyboardPalette(
            colorScheme: .light,
            chassis: Color(hex: 0xC7C7CC),
            chrome: Color(hex: 0xD8D8DC),
            keyFill: .white,
            keyEdge: .black.opacity(0.7),
            keyShadow: .black.opacity(0.3),
            label: .black,
            secondaryLabel: Color(hex: 0x1C1C1E),
            border: .black,
            active: Color(hex: 0x0040DD),
            deadKey: Color(hex: 0xC93400),
            error: Color(hex: 0xD70015),
            emphasizesBorders: true
        ),
        dark: KeyboardPalette(
            colorScheme: .dark,
            chassis: .black,
            chrome: Color(hex: 0x0A0A0A),
            keyFill: Color(hex: 0x1C1C1E),
            keyEdge: Color(hex: 0x3A3A3C),
            keyShadow: .black,
            label: .white,
            secondaryLabel: Color(hex: 0xE5E5EA),
            border: .white.opacity(0.8),
            active: Color(hex: 0xFFD60A),
            deadKey: Color(hex: 0xFF9F0A),
            error: Color(hex: 0xFF6961),
            emphasizesBorders: true
        )
    )

    static let dracula = Self(
        id: "dracula",
        name: "Dracula",
        light: nil,
        dark: .darkTheme(
            chassis: 0x21222C, chrome: 0x282A36, keyFill: 0x343746,
            label: 0xF8F8F2, secondaryLabel: 0xC0C4D8, border: 0x6272A4,
            active: 0xBD93F9, deadKey: 0xFFB86C, error: 0xFF5555
        ),
        group: .community
    )

    static let nord = Self(
        id: "nord",
        name: "Nord",
        light: .lightTheme(
            chassis: 0xD8DEE9, chrome: 0xE5E9F0, keyFill: 0xECEFF4,
            label: 0x2E3440, secondaryLabel: 0x4C566A, ink: 0x4C566A,
            active: 0x5E81AC, deadKey: 0xD08770, error: 0xBF616A
        ),
        dark: .darkTheme(
            chassis: 0x242933, chrome: 0x2E3440, keyFill: 0x3B4252,
            label: 0xECEFF4, secondaryLabel: 0xD8DEE9, border: 0x4C566A,
            active: 0x88C0D0, deadKey: 0xD08770, error: 0xBF616A
        ),
        group: .community
    )

    static let gruvbox = Self(
        id: "gruvbox",
        name: "Gruvbox",
        light: .lightTheme(
            chassis: 0xEBDBB2, chrome: 0xF2E5BC, keyFill: 0xFBF1C7,
            label: 0x3C3836, secondaryLabel: 0x665C54, ink: 0x7C6F64,
            active: 0x076678, deadKey: 0xAF3A03, error: 0x9D0006
        ),
        dark: .darkTheme(
            chassis: 0x1D2021, chrome: 0x282828, keyFill: 0x3C3836,
            label: 0xEBDBB2, secondaryLabel: 0xBDAE93, border: 0x504945,
            active: 0xFABD2F, deadKey: 0xFE8019, error: 0xFB4934
        ),
        group: .community
    )

    static let solarized = Self(
        id: "solarized",
        name: "Solarized",
        light: .lightTheme(
            chassis: 0xEEE8D5, chrome: 0xF5EFDC, keyFill: 0xFDF6E3,
            label: 0x073642, secondaryLabel: 0x586E75, ink: 0x93A1A1,
            active: 0x268BD2, deadKey: 0xCB4B16, error: 0xDC322F
        ),
        dark: .darkTheme(
            chassis: 0x00212B, chrome: 0x002B36, keyFill: 0x073642,
            label: 0xEEE8D5, secondaryLabel: 0x93A1A1, border: 0x586E75,
            active: 0x268BD2, deadKey: 0xCB4B16, error: 0xDC322F
        ),
        group: .community
    )

    static let rosePine = Self(
        id: "rose-pine",
        name: "Rosé Pine",
        light: .lightTheme(
            chassis: 0xF2E9E1, chrome: 0xFAF4ED, keyFill: 0xFFFAF3,
            label: 0x575279, secondaryLabel: 0x797593, ink: 0x9893A5,
            active: 0x907AA9, deadKey: 0xEA9D34, error: 0xB4637A
        ),
        dark: .darkTheme(
            chassis: 0x191724, chrome: 0x1F1D2E, keyFill: 0x26233A,
            label: 0xE0DEF4, secondaryLabel: 0xB3AFCB, border: 0x403D52,
            active: 0xC4A7E7, deadKey: 0xF6C177, error: 0xEB6F92
        ),
        group: .community
    )

    static let oneDark = Self(
        id: "one-dark",
        name: "One Dark",
        light: nil,
        dark: .darkTheme(
            chassis: 0x21252B, chrome: 0x282C34, keyFill: 0x353B45,
            label: 0xDCDFE4, secondaryLabel: 0xABB2BF, border: 0x3E4451,
            active: 0x61AFEF, deadKey: 0xD19A66, error: 0xE06C75
        ),
        group: .community
    )

    static let everforest = Self(
        id: "everforest",
        name: "Everforest",
        light: .lightTheme(
            chassis: 0xE6E2CC, chrome: 0xEFEBD4, keyFill: 0xFDF6E3,
            label: 0x5C6A72, secondaryLabel: 0x829181, ink: 0x939F91,
            active: 0x35A77C, deadKey: 0xF57D26, error: 0xF85552
        ),
        dark: .darkTheme(
            chassis: 0x232A2E, chrome: 0x2D353B, keyFill: 0x3D484D,
            label: 0xD3C6AA, secondaryLabel: 0x9DA9A0, border: 0x475258,
            active: 0xA7C080, deadKey: 0xE69875, error: 0xE67E80
        ),
        group: .community
    )

    static let kanagawa = Self(
        id: "kanagawa",
        name: "Kanagawa",
        light: nil,
        dark: .darkTheme(
            chassis: 0x16161D, chrome: 0x1F1F28, keyFill: 0x2A2A37,
            label: 0xDCD7BA, secondaryLabel: 0xC8C093, border: 0x54546D,
            active: 0x7E9CD8, deadKey: 0xFFA066, error: 0xE46876
        ),
        group: .community
    )

    static let github = Self(
        id: "github",
        name: "GitHub",
        light: .lightTheme(
            chassis: 0xEAEEF2, chrome: 0xF6F8FA, keyFill: 0xFFFFFF,
            label: 0x1F2328, secondaryLabel: 0x59636E, ink: 0x8C959F,
            active: 0x0969DA, deadKey: 0xBC4C00, error: 0xCF222E
        ),
        dark: .darkTheme(
            chassis: 0x0D1117, chrome: 0x161B22, keyFill: 0x21262D,
            label: 0xE6EDF3, secondaryLabel: 0x9DA7B3, border: 0x30363D,
            active: 0x58A6FF, deadKey: 0xFFA657, error: 0xF85149
        ),
        group: .community
    )
}

// MARK: - Palette Builders
extension KeyboardPalette {
    fileprivate static func darkTheme(
        chassis: UInt32,
        chrome: UInt32,
        keyFill: UInt32,
        label: UInt32,
        secondaryLabel: UInt32,
        border: UInt32? = nil,
        active: UInt32,
        deadKey: UInt32,
        error: UInt32
    ) -> Self {
        Self(
            colorScheme: .dark,
            chassis: Color(hex: chassis),
            chrome: Color(hex: chrome),
            keyFill: Color(hex: keyFill),
            keyEdge: .black.opacity(0.65),
            keyShadow: .black.opacity(0.45),
            label: Color(hex: label),
            secondaryLabel: Color(hex: secondaryLabel),
            border: border.map { Color(hex: $0, opacity: 0.45) } ?? .white.opacity(0.06),
            active: Color(hex: active),
            deadKey: Color(hex: deadKey),
            error: Color(hex: error)
        )
    }

    /// `ink` is the theme's muted tone, used for key edges, shadows, and borders.
    fileprivate static func lightTheme(
        chassis: UInt32,
        chrome: UInt32,
        keyFill: UInt32,
        label: UInt32,
        secondaryLabel: UInt32,
        ink: UInt32,
        active: UInt32,
        deadKey: UInt32,
        error: UInt32
    ) -> Self {
        Self(
            colorScheme: .light,
            chassis: Color(hex: chassis),
            chrome: Color(hex: chrome),
            keyFill: Color(hex: keyFill),
            keyEdge: Color(hex: ink, opacity: 0.4),
            keyShadow: Color(hex: ink, opacity: 0.25),
            label: Color(hex: label),
            secondaryLabel: Color(hex: secondaryLabel),
            border: Color(hex: ink, opacity: 0.3),
            active: Color(hex: active),
            deadKey: Color(hex: deadKey),
            error: Color(hex: error)
        )
    }
}
