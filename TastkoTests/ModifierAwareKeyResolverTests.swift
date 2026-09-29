import Testing

@testable import Tastko

// MARK: - ModifierAwareKeyResolverTests
@MainActor
struct ModifierAwareKeyResolverTests {
    // MARK: - Presentation
    @Test func labelsFollowTheResolvedLeftAndRightActions() throws {
        let translator = try keyboardLayoutTranslator("com.apple.keylayout.US")
        let normalLabels: [(Key, String, String?)] = [
            (.a, "a", nil), (.two, "2", "@"), (.semicolon, ";", ":"),
            (.comma, ",", "<"),
        ]
        for (key, title, secondaryTitle) in normalLabels {
            let normal = ModifierAwareKeyResolver.presentation(
                from: base(key),
                translator: translator,
                latchedModifiers: [],
                physicalModifiers: [],
                isCapsLockEnabled: false
            )
            #expect(normal.title == title)
            #expect(normal.secondaryTitle == secondaryTitle)
            #expect(normal.rightClickAction == .keyStroke(KeyStroke(key, modifiers: [.shift])))
        }
        let option = ModifierAwareKeyResolver.presentation(
            from: base(.two),
            translator: translator,
            latchedModifiers: [.leftOption],
            physicalModifiers: [],
            isCapsLockEnabled: false
        )
        #expect(option.title == "™")
        #expect(option.secondaryTitle == "€")
        #expect(option.leftClickAction == .keyStroke(KeyStroke(.two, modifiers: [.option])))
        #expect(
            option.rightClickAction == .keyStroke(KeyStroke(.two, modifiers: [.option, .shift]))
        )
        let shifted = ModifierAwareKeyResolver.presentation(
            from: base(.two),
            translator: translator,
            latchedModifiers: [.leftOption],
            physicalModifiers: [.rightShift],
            isCapsLockEnabled: false
        )
        #expect(shifted.title == "€")
        #expect(shifted.secondaryTitle == nil)
        #expect(shifted.leftClickAction == option.rightClickAction)
        let caps = ModifierAwareKeyResolver.presentation(
            from: base(.a),
            translator: translator,
            latchedModifiers: [],
            physicalModifiers: [],
            isCapsLockEnabled: true
        )
        #expect(caps.title == "A")
        #expect(caps.secondaryTitle == nil)
        #expect(caps.leftClickAction == .keyStroke(KeyStroke(.a, modifiers: [.capsLock])))
        #expect(caps.rightClickAction == .keyStroke(KeyStroke(.a)))
    }

    @Test func customTextAndShortcutLabelsArePreserved() throws {
        let translator = try keyboardLayoutTranslator("com.apple.keylayout.US")
        let cases: [(KeyAction, KeyAction)] = [
            (.text("Hello"), .text("Hello")),
            (
                .keyStroke(KeyStroke(.c, modifiers: [.command])),
                .keyStroke(KeyStroke(.c, modifiers: [.command, .option]))
            ),
        ]
        for (action, expectedAction) in cases {
            let custom = ResolvedKey(
                title: "Custom",
                secondaryTitle: nil,
                leftClickAction: action,
                rightClickAction: .none
            )
            let resolved = ModifierAwareKeyResolver.presentation(
                from: custom,
                translator: translator,
                latchedModifiers: [.leftOption],
                physicalModifiers: [],
                isCapsLockEnabled: false
            )
            #expect(resolved.title == custom.title)
            #expect(resolved.secondaryTitle == custom.secondaryTitle)
            #expect(resolved.leftClickAction == expectedAction)
        }
        #expect(translator.label(for: KeyStroke(.a, modifiers: [.command])) == nil)
    }

    @Test func unsupportedLayoutsKeepLabelsAndSecondaryActions() {
        let original = ResolvedKey(
            title: "A",
            secondaryTitle: nil,
            leftClickAction: .keyStroke(KeyStroke(.a)),
            rightClickAction: .none
        )
        let resolved = ModifierAwareKeyResolver.presentation(
            from: original,
            translator: KeyboardLayoutTranslator(),
            latchedModifiers: [],
            physicalModifiers: [.rightOption],
            isCapsLockEnabled: false
        )
        #expect(resolved.title == "A")
        #expect(resolved.secondaryTitle == nil)
        #expect(resolved.leftClickAction == .keyStroke(KeyStroke(.a, modifiers: [.option])))
        #expect(resolved.rightClickAction == .none)
    }

    @Test func customSecondaryActionsKeepTheirLabelsAndDelivery() throws {
        let original = ResolvedKey(
            title: "A",
            secondaryTitle: "Template",
            leftClickAction: .keyStroke(KeyStroke(.a)),
            rightClickAction: .text("Template")
        )
        let resolved = ModifierAwareKeyResolver.presentation(
            from: original,
            translator: try keyboardLayoutTranslator("com.apple.keylayout.US"),
            latchedModifiers: [],
            physicalModifiers: [.rightShift],
            isCapsLockEnabled: false
        )
        #expect(resolved.title == "A")
        #expect(resolved.secondaryTitle == "Template")
        #expect(resolved.leftClickAction == .text("Template"))
        #expect(resolved.rightClickAction == .text("Template"))
    }

    @Test func accentPresentationRetainsTheComposingKeystroke() throws {
        let resolved = ModifierAwareKeyResolver.presentation(
            from: base(.e),
            translator: try keyboardLayoutTranslator("com.apple.keylayout.US"),
            latchedModifiers: [.leftOption],
            physicalModifiers: [],
            isCapsLockEnabled: false
        )
        #expect(resolved.isDeadKey)
        #expect(resolved.leftClickAction == .keyStroke(KeyStroke(.e, modifiers: [.option])))
    }

    // MARK: - Fixtures
    private func base(_ key: Key) -> ResolvedKey {
        ResolvedKey(
            title: key == .a ? "A" : "Key",
            secondaryTitle: nil,
            leftClickAction: .keyStroke(KeyStroke(key)),
            rightClickAction: .keyStroke(KeyStroke(key, modifiers: [.shift]))
        )
    }
}
