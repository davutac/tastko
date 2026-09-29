import Foundation

// MARK: - KeyboardLanguageLayout
nonisolated enum KeyboardLanguageLayout: Equatable {
    case base
    case qwertz

    // MARK: - Resolution
    static func resolved(for context: KeyboardLanguageContext) -> KeyboardLanguageLayout {
        if isGermanLanguageCode(context.primaryLanguageCode) {
            return .qwertz
        }

        return context.languageIdentifiers.contains(where: isGermanLayoutIdentifier)
            ? .qwertz : .base
    }

    private static func isGermanLanguageCode(_ languageCode: String?) -> Bool {
        guard let languageCode else {
            return false
        }

        let normalizedCode =
            languageCode
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")

        return normalizedCode == "de" || normalizedCode.hasPrefix("de-")
    }

    private static func isGermanLayoutIdentifier(_ identifier: String) -> Bool {
        let normalizedIdentifier = identifier.lowercased()

        return normalizedIdentifier.contains("qwertz")
            || normalizedIdentifier.contains("german")
            || normalizedIdentifier.contains("deutsch")
    }
}

// MARK: - KeyboardLanguageContext
nonisolated struct KeyboardLanguageContext: Equatable, Hashable {
    let languageCodes: [String]
    let languageIdentifiers: [String]

    // MARK: - Initialization
    init(
        languageCodes: [String] = [],
        languageIdentifiers: [String] = []
    ) {
        self.languageCodes = languageCodes
        self.languageIdentifiers = languageIdentifiers
    }

    init(language: KeyboardLanguage?) {
        guard let language else {
            self.init()
            return
        }

        self.init(
            languageCodes: language.languageCodes,
            languageIdentifiers: [
                language.id,
                language.name,
            ]
        )
    }

    var primaryLanguageCode: String? {
        languageCodes.first
    }
}

// MARK: - LanguageAwareKeyResolver
nonisolated enum LanguageAwareKeyResolver {
    // MARK: - Presentation
    static func presentation(
        title: String,
        secondaryTitle: String,
        leftClickAction: KeyAction,
        rightClickAction: KeyAction,
        languageContext: KeyboardLanguageContext
    ) -> ResolvedKey {
        let basePresentation = ResolvedKey(
            title: title,
            secondaryTitle: secondaryTitle.isEmpty ? nil : secondaryTitle,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction
        )

        guard
            KeyboardLanguageLayout.resolved(for: languageContext) == .qwertz,
            case .keyStroke(let primaryStroke) = leftClickAction,
            primaryStroke.modifiers.isEmpty,
            let overlay = QwertzOverlay.overlay(for: primaryStroke.key)
        else {
            return basePresentation
        }

        let rightClickAction = resolvedRightClickAction(
            currentAction: rightClickAction,
            primaryKey: primaryStroke.key,
            overlay: overlay
        )

        return ResolvedKey(
            title: overlay.title,
            secondaryTitle: resolvedSecondaryTitle(
                currentAction: rightClickAction,
                baseSecondaryTitle: basePresentation.secondaryTitle,
                overlay: overlay
            ),
            leftClickAction: .keyStroke(KeyStroke(primaryStroke.key)),
            rightClickAction: rightClickAction
        )
    }

    // MARK: - Secondary Action
    private static func resolvedRightClickAction(
        currentAction: KeyAction,
        primaryKey: Key,
        overlay: QwertzOverlay
    ) -> KeyAction {
        guard
            overlay.secondaryTitle != nil,
            isShiftedStroke(currentAction, for: primaryKey)
        else {
            return currentAction
        }

        return .keyStroke(KeyStroke(primaryKey, modifiers: [.shift]))
    }

    private static func resolvedSecondaryTitle(
        currentAction: KeyAction,
        baseSecondaryTitle: String?,
        overlay: QwertzOverlay
    ) -> String? {
        guard isShiftedStroke(currentAction, for: overlay.key) else {
            return baseSecondaryTitle
        }

        return overlay.secondaryTitle
    }

    private static func isShiftedStroke(_ action: KeyAction, for key: Key) -> Bool {
        guard case .keyStroke(let stroke) = action else {
            return false
        }

        return stroke.key == key && stroke.modifiers == [.shift]
    }
}

// MARK: - QwertzOverlay
nonisolated private struct QwertzOverlay: Equatable {
    let key: Key
    let title: String
    let secondaryTitle: String?

    // MARK: - Lookup
    static func overlay(for key: Key) -> QwertzOverlay? {
        overlays[key]
    }

    private static let overlays: [Key: QwertzOverlay] = [
        .grave: QwertzOverlay(key: .grave, title: "<", secondaryTitle: ">"),
        .minus: QwertzOverlay(key: .minus, title: "ß", secondaryTitle: "?"),
        .equal: QwertzOverlay(key: .equal, title: "´", secondaryTitle: "`"),
        .y: QwertzOverlay(key: .y, title: "Z", secondaryTitle: nil),
        .z: QwertzOverlay(key: .z, title: "Y", secondaryTitle: nil),
        .leftBracket: QwertzOverlay(key: .leftBracket, title: "Ü", secondaryTitle: nil),
        .rightBracket: QwertzOverlay(key: .rightBracket, title: "+", secondaryTitle: "*"),
        .semicolon: QwertzOverlay(key: .semicolon, title: "Ö", secondaryTitle: nil),
        .quote: QwertzOverlay(key: .quote, title: "Ä", secondaryTitle: nil),
        .backslash: QwertzOverlay(key: .backslash, title: "#", secondaryTitle: "'"),
        .isoSection: QwertzOverlay(key: .isoSection, title: "^", secondaryTitle: "°"),
        .comma: QwertzOverlay(key: .comma, title: ",", secondaryTitle: ";"),
        .period: QwertzOverlay(key: .period, title: ".", secondaryTitle: ":"),
        .slash: QwertzOverlay(key: .slash, title: "-", secondaryTitle: "_"),
    ]
}
