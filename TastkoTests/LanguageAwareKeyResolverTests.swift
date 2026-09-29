import Testing

@testable import Tastko

// MARK: - LanguageAwareKeyResolverTests
struct LanguageAwareKeyResolverTests {
    // MARK: - Resolution
    @Test func defaultLanguageUsesBaseKeyPresentation() {
        let resolvedKey = presentation(languageCodes: [])

        #expect(resolvedKey.title == "Y")
        #expect(resolvedKey.secondaryTitle == nil)
        #expect(resolvedKey.leftClickAction == .keyStroke(KeyStroke(.y)))
        #expect(resolvedKey.rightClickAction == .keyStroke(KeyStroke(.y, modifiers: [.shift])))
    }

    @Test func englishLanguageUsesBaseKeyPresentation() {
        let resolvedKey = presentation(languageCodes: ["en-US"])

        #expect(resolvedKey.title == "Y")
        #expect(resolvedKey.leftClickAction == .keyStroke(KeyStroke(.y)))
        #expect(resolvedKey.rightClickAction == .keyStroke(KeyStroke(.y, modifiers: [.shift])))
    }

    @Test func englishInputSourceWithGermanFallbackCodeUsesBaseKeyPresentation() {
        let resolvedKey = presentation(languageCodes: ["en", "de"])

        #expect(resolvedKey.title == "Y")
        #expect(resolvedKey.leftClickAction == .keyStroke(KeyStroke(.y)))
        #expect(resolvedKey.rightClickAction == .keyStroke(KeyStroke(.y, modifiers: [.shift])))
    }

    @Test func germanLanguageSwapsPhysicalYAndZLabels() {
        let resolvedYKey = presentation(languageCodes: ["de-DE"])
        let resolvedZKey = presentation(
            title: "Z",
            leftClickAction: .keyStroke(KeyStroke(.z)),
            rightClickAction: .keyStroke(KeyStroke(.z, modifiers: [.shift])),
            languageCodes: ["de-DE"]
        )

        #expect(resolvedYKey.title == "Z")
        #expect(resolvedYKey.leftClickAction == .keyStroke(KeyStroke(.y)))
        #expect(resolvedYKey.rightClickAction == .keyStroke(KeyStroke(.y, modifiers: [.shift])))
        #expect(resolvedZKey.title == "Y")
        #expect(resolvedZKey.leftClickAction == .keyStroke(KeyStroke(.z)))
        #expect(resolvedZKey.rightClickAction == .keyStroke(KeyStroke(.z, modifiers: [.shift])))
    }

    @Test func germanLanguageResolvesPunctuationLabels() {
        let minusKey = presentation(
            title: "-",
            secondaryTitle: "_",
            leftClickAction: .keyStroke(KeyStroke(.minus)),
            rightClickAction: .keyStroke(KeyStroke(.minus, modifiers: [.shift])),
            languageCodes: ["de-DE"]
        )
        let isoSectionKey = presentation(
            title: "§",
            secondaryTitle: "±",
            leftClickAction: .keyStroke(KeyStroke(.isoSection)),
            rightClickAction: .keyStroke(KeyStroke(.isoSection, modifiers: [.shift])),
            languageCodes: ["de-DE"]
        )
        let graveKey = presentation(
            title: "`",
            secondaryTitle: "~",
            leftClickAction: .keyStroke(KeyStroke(.grave)),
            rightClickAction: .keyStroke(KeyStroke(.grave, modifiers: [.shift])),
            languageCodes: ["de-DE"]
        )

        #expect(minusKey.title == "ß")
        #expect(minusKey.secondaryTitle == "?")
        #expect(minusKey.leftClickAction == .keyStroke(KeyStroke(.minus)))
        #expect(minusKey.rightClickAction == .keyStroke(KeyStroke(.minus, modifiers: [.shift])))
        #expect(isoSectionKey.title == "^")
        #expect(isoSectionKey.secondaryTitle == "°")
        #expect(isoSectionKey.leftClickAction == .keyStroke(KeyStroke(.isoSection)))
        #expect(
            isoSectionKey.rightClickAction
                == .keyStroke(KeyStroke(.isoSection, modifiers: [.shift]))
        )
        #expect(graveKey.title == "<")
        #expect(graveKey.secondaryTitle == ">")
        #expect(graveKey.leftClickAction == .keyStroke(KeyStroke(.grave)))
        #expect(graveKey.rightClickAction == .keyStroke(KeyStroke(.grave, modifiers: [.shift])))
    }

    @Test func germanLanguageLeavesCustomPrimaryActionsUnchanged() {
        let resolvedKey = presentation(
            title: "Paste",
            secondaryTitle: "Template",
            leftClickAction: .text("custom"),
            rightClickAction: .text("secondary"),
            languageCodes: ["de-DE"]
        )

        #expect(resolvedKey.title == "Paste")
        #expect(resolvedKey.secondaryTitle == "Template")
        #expect(resolvedKey.leftClickAction == .text("custom"))
        #expect(resolvedKey.rightClickAction == .text("secondary"))
    }

    @Test func germanLanguageWithShiftedSecondaryActionKeepsPhysicalKeyCode() {
        let resolvedKey = presentation(
            title: "/",
            secondaryTitle: "?",
            leftClickAction: .keyStroke(KeyStroke(.slash)),
            rightClickAction: .keyStroke(KeyStroke(.slash, modifiers: [.shift])),
            languageCodes: ["de-CH"]
        )

        #expect(resolvedKey.title == "-")
        #expect(resolvedKey.secondaryTitle == "_")
        #expect(resolvedKey.leftClickAction == .keyStroke(KeyStroke(.slash)))
        #expect(resolvedKey.rightClickAction == .keyStroke(KeyStroke(.slash, modifiers: [.shift])))
    }

    @Test func germanLayoutIdentifierUsesQwertzOverlayWhenLanguageCodeIsNotGerman() {
        let resolvedKey = presentation(
            languageCodes: ["en-US"],
            languageIdentifiers: ["com.apple.keylayout.German"]
        )

        #expect(resolvedKey.title == "Z")
        #expect(resolvedKey.leftClickAction == .keyStroke(KeyStroke(.y)))
    }

    // MARK: - Helpers
    private func presentation(
        title: String = "Y",
        secondaryTitle: String = "",
        leftClickAction: KeyAction = .keyStroke(KeyStroke(.y)),
        rightClickAction: KeyAction = .keyStroke(KeyStroke(.y, modifiers: [.shift])),
        languageCodes: [String],
        languageIdentifiers: [String] = []
    ) -> ResolvedKey {
        LanguageAwareKeyResolver.presentation(
            title: title,
            secondaryTitle: secondaryTitle,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction,
            languageContext: KeyboardLanguageContext(
                languageCodes: languageCodes,
                languageIdentifiers: languageIdentifiers
            )
        )
    }
}
