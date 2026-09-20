import CoreGraphics
import Foundation
import Testing

@testable import Tastko

// MARK: - Caps Lock
extension KeyboardServiceTests {
    // MARK: - Caps Lock Source Regression
    @Test func systemCapsLockDrivesLabelsAndTypingDespiteStaleHIDFlags() throws {
        var systemLock = true
        let physical = PhysicalKeyboardState(
            readHardware: {
                PhysicalKeyboardState.hardwareSnapshot(
                    pressedKeys: [.capsLock],
                    flags: [],
                    capsLockEnabled: systemLock
                )
            },
            canObserve: { true }
        )
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(target: keyboardServiceTarget()),
            eventPoster: poster,
            physicalKeyboard: physical,
            toggleSystemCapsLock: {
                systemLock.toggle()
                return systemLock
            }
        )
        let translator = try keyboardLayoutTranslator("com.apple.keylayout.US")
        // Include startup, external changes, and a verified virtual toggle followed by refresh.
        for enabled in [true, false, true] {
            systemLock = enabled
            physical.refresh()
            #expect(service.effectiveCapsLockEnabled == enabled)
            #expect(!physical.snapshot.isPressed(.keyStroke(KeyStroke(.capsLock))))
            let presentation = ModifierAwareKeyResolver.presentation(
                from: ResolvedKeyPresentation(
                    title: "A",
                    secondaryTitle: nil,
                    leftClickAction: .keyStroke(KeyStroke(.a)),
                    rightClickAction: .keyStroke(KeyStroke(.a, modifiers: [.shift]))
                ),
                translator: translator,
                activeOneShotModifiers: service.activeOneShotModifiers,
                physicalModifiers: service.heldModifiers,
                isCapsLockEnabled: service.effectiveCapsLockEnabled
            )
            #expect(presentation.title == (enabled ? "A" : "a"))
            guard case .keyStroke(let stroke) = presentation.leftClickAction else {
                Issue.record("Expected a letter keystroke")
                return
            }
            try service.press(stroke, latchedModifiers: [], modifiersAreResolved: true)
            let flags: KeyModifiers = enabled ? [.capsLock] : []
            #expect(
                Array(poster.events.suffix(2)) == [
                    .key(.a, flags, true), .key(.a, flags, false),
                ]
            )
        }
        try service.toggleCapsLock()
        physical.refresh()
        #expect(service.effectiveCapsLockEnabled == false)
        #expect(!physical.snapshot.isPressed(.keyStroke(KeyStroke(.capsLock))))
        try service.toggleCapsLock()
        physical.refresh()
        #expect(service.effectiveCapsLockEnabled)
        #expect(!physical.snapshot.isPressed(.keyStroke(KeyStroke(.capsLock))))
    }

    // MARK: - Caps Lock
    @Test func capsLockTogglesInjectedSystemStateAndPreservesStickyModifiers() async throws {
        let resolver = FakeKeyboardTargetResolver(target: keyboardServiceTarget())
        let poster = FakeKeyboardEventPoster()
        var capsLockEnabled = false
        var toggleCount = 0
        let physical = PhysicalKeyboardState(
            readHardware: { PhysicalKeyboardSnapshot(isCapsLockEnabled: capsLockEnabled) },
            canObserve: { true }
        )
        let service = KeyboardService(
            targetResolver: resolver,
            eventPoster: poster,
            physicalKeyboard: physical,
            toggleSystemCapsLock: {
                toggleCount += 1
                capsLockEnabled.toggle()
                return capsLockEnabled
            }
        )

        let receipt = try await service.perform(.keyStroke(KeyStroke(.capsLock)))

        #expect(receipt.method == .keyEvent)
        #expect(
            poster.events == [
                .key(.capsLock, [.capsLock], true), .key(.capsLock, [.capsLock], false),
            ]
        )
        #expect(service.isCapsLockEnabled)
        #expect(physical.snapshot.isCapsLockEnabled)
        #expect(toggleCount == 1)

        try service.toggleOneShotModifier(.leftShift)
        try await service.perform(.text("test"))
        try await service.perform(.keyStroke(KeyStroke(.space)))
        service.releaseAllModifiers()
        #expect(service.isCapsLockEnabled)
        #expect(toggleCount == 1)
        #expect(
            poster.events == [
                .key(.capsLock, [.capsLock], true), .key(.capsLock, [.capsLock], false),
                .key(.leftShift, [.shift, .capsLock], true),
                .text("test", 1234, .textElement),
                .key(.leftShift, [.capsLock], false),
                .key(.space, [.capsLock], true), .key(.space, [.capsLock], false),
            ]
        )

        try service.toggleOneShotModifier(.leftShift)
        try await service.perform(.keyStroke(KeyStroke(.capsLock)))
        #expect(service.isCapsLockEnabled == false)
        #expect(capsLockEnabled == false)
        #expect(toggleCount == 2)
        #expect(service.activeOneShotModifiers == [.leftShift])
        #expect(
            Array(poster.events.suffix(3)) == [
                .key(.leftShift, [.shift, .capsLock], true),
                .key(.capsLock, [.shift], true), .key(.capsLock, [.shift], false),
            ]
        )
        service.releaseAllModifiers()
        #expect(poster.events.last == .key(.leftShift, [], false))
    }

    @Test func capsLockRemainsEnabledAfterUppercaseAndLowercaseClicks() throws {
        let resolver = FakeKeyboardTargetResolver(target: keyboardServiceTarget())
        let poster = FakeKeyboardEventPoster()
        var capsLockEnabled = false
        let physical = PhysicalKeyboardState(
            readHardware: { PhysicalKeyboardSnapshot(isCapsLockEnabled: capsLockEnabled) },
            canObserve: { true }
        )
        let service = KeyboardService(
            targetResolver: resolver,
            eventPoster: poster,
            physicalKeyboard: physical,
            toggleSystemCapsLock: {
                capsLockEnabled.toggle()
                return capsLockEnabled
            }
        )
        try service.toggleCapsLock()

        for trigger in [KeyActionTrigger.leftClick, .rightClick, .leftClick] {
            try service.toggleOneShotModifier(.leftShift)
            let action = KeyActionResolver.action(
                for: trigger,
                primaryAction: .keyStroke(KeyStroke(.a)),
                secondaryAction: .keyStroke(KeyStroke(.a, modifiers: [.shift])),
                activeOneShotModifiers: service.activeOneShotModifiers,
                isCapsLockEnabled: service.isCapsLockEnabled,
                primaryTitle: "A"
            )
            let modifiers = service.consumeActiveOneShotModifiers(for: action)
            guard case .keyStroke(let stroke) = action else {
                Issue.record("Expected a letter keystroke")
                return
            }
            #expect(modifiers.isEmpty, "Resolved Caps Lock letter clicks must discard sticky Shift")
            try service.press(stroke, latchedModifiers: modifiers, modifiersAreResolved: true)
            #expect(service.isCapsLockEnabled)
            #expect(capsLockEnabled)
        }

        #expect(
            poster.events == [
                .key(.capsLock, [.capsLock], true), .key(.capsLock, [.capsLock], false),
                .key(.leftShift, [.shift, .capsLock], true),
                .key(.leftShift, [.capsLock], false),
                .key(.a, [.capsLock], true), .key(.a, [.capsLock], false),
                .key(.leftShift, [.shift, .capsLock], true),
                .key(.leftShift, [.capsLock], false),
                .key(.a, [], true), .key(.a, [], false),
                .key(.leftShift, [.shift, .capsLock], true),
                .key(.leftShift, [.capsLock], false),
                .key(.a, [.capsLock], true), .key(.a, [.capsLock], false),
            ]
        )
        #expect(service.activeOneShotModifiers.isEmpty)
    }

    // MARK: - Caps Lock Failure
    @Test func failedSystemCapsLockToggleDoesNotChangePhysicalStateOrPostEvents() throws {
        let state = FailingCapsLockState()
        let physical = PhysicalKeyboardState(
            readHardware: { PhysicalKeyboardSnapshot(isCapsLockEnabled: state.isEnabled) },
            canObserve: { true }
        )
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster,
            physicalKeyboard: physical,
            toggleSystemCapsLock: { try state.toggle() }
        )
        #expect(throws: KeyboardServiceError.deliveryFailed("Caps Lock unavailable")) {
            try service.toggleCapsLock()
        }
        #expect(service.lastError == .deliveryFailed("Caps Lock unavailable"))
        #expect(service.isCapsLockEnabled == false)
        #expect(state.isEnabled == false)
        #expect(poster.events.isEmpty)
        state.shouldFail = false
        try service.toggleCapsLock()
        #expect(service.isCapsLockEnabled)
        #expect(service.lastError == nil)
        #expect(
            poster.events == [
                .key(.capsLock, [.capsLock], true), .key(.capsLock, [.capsLock], false),
            ]
        )
    }
}
