import Testing

@testable import Tastko

// MARK: - KeyActionResolverTests
struct KeyActionResolverTests {
    // MARK: - Caps Lock
    @Test func capsLockDoesNotRepeatWhileHeld() {
        let action = KeyAction.keyStroke(KeyStroke(.capsLock))
        #expect(action.isModifier)
        #expect(!action.isRepeatable)
    }

    @Test(arguments: [KeyActionTrigger.leftClick, .rightClick])
    func capsLockControlsLetterCase(_ trigger: KeyActionTrigger) {
        let action = KeyActionResolver.action(
            for: trigger,
            primaryAction: .keyStroke(KeyStroke(.a)),
            secondaryAction: .keyStroke(KeyStroke(.a, modifiers: [.shift])),
            latchedModifiers: [],
            isCapsLockEnabled: true,
            primaryTitle: "A"
        )
        let flags: KeyModifiers = trigger == .leftClick ? [.capsLock] : []
        #expect(action == .keyStroke(KeyStroke(.a, modifiers: flags)))
    }

    @Test func capsLockRightClickUsesLowercaseEvenWithoutASecondaryAction() {
        let action = KeyActionResolver.action(
            for: .rightClick,
            primaryAction: .keyStroke(KeyStroke(.semicolon)),
            secondaryAction: .none,
            latchedModifiers: [.leftShift],
            isCapsLockEnabled: true,
            primaryTitle: "Ö"
        )
        #expect(action == .keyStroke(KeyStroke(.semicolon)))
    }

    @Test func capsLockPreservesNumberAndPunctuationActions() {
        for trigger in [KeyActionTrigger.leftClick, .rightClick] {
            let action = KeyActionResolver.action(
                for: trigger,
                primaryAction: .keyStroke(KeyStroke(.one)),
                secondaryAction: .keyStroke(KeyStroke(.one, modifiers: [.shift])),
                latchedModifiers: [],
                isCapsLockEnabled: true,
                primaryTitle: "1"
            )
            let flags: KeyModifiers = trigger == .rightClick ? [.shift] : []
            #expect(action == .keyStroke(KeyStroke(.one, modifiers: flags)))
        }
    }

    @Test func capsLockChangesTextActionCase() {
        for trigger in [KeyActionTrigger.leftClick, .rightClick] {
            let action = KeyActionResolver.action(
                for: trigger,
                primaryAction: .text("Hello ä"),
                secondaryAction: .none,
                latchedModifiers: [],
                isCapsLockEnabled: true
            )
            #expect(action == .text(trigger == .leftClick ? "HELLO Ä" : "hello ä"))
        }
    }

    @Test func capsLockDoesNotChangeKeyboardShortcuts() {
        let action = KeyActionResolver.action(
            for: .leftClick,
            primaryAction: .keyStroke(KeyStroke(.s)),
            secondaryAction: .keyStroke(KeyStroke(.s, modifiers: [.shift])),
            latchedModifiers: [.leftCommand, .leftShift],
            isCapsLockEnabled: true,
            primaryTitle: "S"
        )
        #expect(action == .keyStroke(KeyStroke(.s, modifiers: [.command, .shift])))
    }

    // MARK: - Physical Modifiers
    @Test func physicalChangesUpdateRepeatsWithoutLosingCapturedOneShotModifiers() {
        let captured: Set<ModifierKey> = [.leftOption]
        for physical: Set<ModifierKey> in [[.rightShift], []] {
            let action = KeyActionResolver.action(
                for: .leftClick,
                primaryAction: .keyStroke(KeyStroke(.two)),
                secondaryAction: .keyStroke(KeyStroke(.two, modifiers: [.shift])),
                latchedModifiers: captured,
                physicalModifiers: physical
            )
            let flags: KeyModifiers = physical.isEmpty ? [.option] : [.option, .shift]
            #expect(action == .keyStroke(KeyStroke(.two, modifiers: flags)))
        }
    }

    @Test func physicalOptionRightClickIncludesShiftAndCapsLock() {
        let action = KeyActionResolver.action(
            for: .rightClick,
            primaryAction: .keyStroke(KeyStroke(.a)),
            secondaryAction: .keyStroke(KeyStroke(.a, modifiers: [.shift])),
            latchedModifiers: [],
            physicalModifiers: [.rightOption],
            isCapsLockEnabled: true,
            primaryTitle: "A"
        )
        #expect(action == .keyStroke(KeyStroke(.a, modifiers: [.option, .shift, .capsLock])))
    }

    // MARK: - Resolution
    @Test func leftClickUsesPrimaryActionWithoutShift() {
        let action = KeyActionResolver.action(
            for: .leftClick,
            primaryAction: .keyStroke(KeyStroke(.one)),
            secondaryAction: .keyStroke(KeyStroke(.one, modifiers: [.shift])),
            latchedModifiers: []
        )

        #expect(action == .keyStroke(KeyStroke(.one)))
    }

    @Test func rightClickUsesSecondaryAction() {
        let action = KeyActionResolver.action(
            for: .rightClick,
            primaryAction: .keyStroke(KeyStroke(.one)),
            secondaryAction: .keyStroke(KeyStroke(.one, modifiers: [.shift])),
            latchedModifiers: []
        )

        #expect(action == .keyStroke(KeyStroke(.one, modifiers: [.shift])))
    }

    @Test func leftClickWithActiveShiftUsesSecondaryAction() {
        let action = KeyActionResolver.action(
            for: .leftClick,
            primaryAction: .keyStroke(KeyStroke(.one)),
            secondaryAction: .keyStroke(KeyStroke(.one, modifiers: [.shift])),
            latchedModifiers: [.leftShift]
        )

        #expect(action == .keyStroke(KeyStroke(.one, modifiers: [.shift])))
    }

    @Test func leftClickWithActiveShiftFallsBackToPrimaryWhenSecondaryActionIsNone() {
        let action = KeyActionResolver.action(
            for: .leftClick,
            primaryAction: .keyStroke(KeyStroke(.one)),
            secondaryAction: .none,
            latchedModifiers: [.leftShift]
        )

        #expect(action == .keyStroke(KeyStroke(.one, modifiers: [.shift])))
    }

    @Test func modifierPrimaryBypassesShiftSecondaryAction() {
        let action = KeyActionResolver.action(
            for: .leftClick,
            primaryAction: .modifier(.leftShift),
            secondaryAction: .keyStroke(KeyStroke(.one, modifiers: [.shift])),
            latchedModifiers: [.leftShift]
        )

        #expect(action == .modifier(.leftShift))
    }

    @Test func resolvedKeyStrokeSnapshotsAllActiveModifiers() {
        let action = KeyActionResolver.action(
            for: .leftClick,
            primaryAction: .keyStroke(KeyStroke(.s)),
            secondaryAction: .keyStroke(KeyStroke(.s, modifiers: [.shift])),
            latchedModifiers: [.leftCommand, .leftShift]
        )

        #expect(action == .keyStroke(KeyStroke(.s, modifiers: [.command, .shift])))
    }
}
