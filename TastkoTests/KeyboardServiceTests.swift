import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import Tastko

// MARK: - KeyboardServiceTests
@MainActor
struct KeyboardServiceTests {
    // MARK: - Lock-Screen Input
    @Test func lockedInputUsesSystemFocusWithoutReadingFieldsOrRetainingKeyReceipts() throws {
        let resolver = FakeKeyboardTargetResolver(error: AccessibilityFocusError.secureTextInput)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: resolver,
            eventPoster: poster,
            canPostEvents: { true }
        )
        var predictionNotifications = 0
        service.inputDidChange = { predictionNotifications += 1 }
        service.setScreenLocked(true, allowsInput: true)
        try service.tap(KeyStroke(.x))
        try service.tap(KeyStroke(.delete))
        let receipt = try service.type("ä")
        #expect(
            poster.events == [
                .key(.x, [], true), .key(.x, [], false),
                .key(.delete, [], true), .key(.delete, [], false),
                .systemText("ä"),
            ]
        )
        #expect(resolver.resolveCount == 0)
        #expect(service.lastReceipt == nil)
        #expect(receipt.processIdentifier == nil && receipt.route == nil)
        #expect(!receipt.summary.contains("ä"))
        #expect(predictionNotifications == 0)
    }

    @Test func lockedModifiersStillProducePairedChordEvents() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(
                error: AccessibilityFocusError.secureTextInput
            ),
            eventPoster: poster,
            canPostEvents: { true }
        )
        service.setScreenLocked(true, allowsInput: true)
        try service.toggleLatch(.leftShift)
        try service.tap(KeyStroke(.x, modifiers: [.shift]))
        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true),
                .key(.x, [.shift], true), .key(.x, [.shift], false),
                .key(.leftShift, [], false),
            ]
        )
        #expect(service.latchedModifiers.isEmpty)
    }

    @Test func lockedPermissionDenialPostsNothingAndDoesNotResolveAnyTarget() {
        let resolver = FakeKeyboardTargetResolver(error: AccessibilityFocusError.secureTextInput)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: resolver,
            eventPoster: poster,
            canPostEvents: { false }
        )
        service.setScreenLocked(true, allowsInput: true)
        #expect(throws: KeyboardServiceError.self) { try service.type("x") }
        #expect(throws: KeyboardServiceError.self) { try service.tap(KeyStroke(.x)) }
        #expect(throws: KeyboardServiceError.accessibility(.accessibilityNotAuthorized)) {
            try service.toggleLatch(.leftShift)
        }
        #expect(throws: KeyboardServiceError.accessibility(.accessibilityNotAuthorized)) {
            try service.toggleFunction()
        }
        #expect(service.latchedModifiers.isEmpty)
        #expect(service.heldModifiers.isEmpty)
        #expect(poster.events.isEmpty)
        #expect(resolver.resolveCount == 0)
    }

    @Test func lockedModeRejectsQueuedPredictionsAndUnlockRestoresSecureTargetExclusion() throws {
        let resolver = FakeKeyboardTargetResolver(error: AccessibilityFocusError.secureTextInput)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: resolver,
            eventPoster: poster,
            canPostEvents: { true }
        )
        try service.toggleLatch(.leftCommand)
        let beforeLock = service.inputSession
        service.setScreenLocked(true, allowsInput: true)
        #expect(service.inputSession != beforeLock)
        #expect(service.latchedModifiers.isEmpty)
        #expect(throws: KeyboardServiceError.self) {
            try service.insertPrediction("old suggestion", into: keyboardServiceTarget())
        }
        let lockedSession = service.inputSession
        service.setScreenLocked(false, allowsInput: false)
        #expect(service.inputSession != lockedSession)
        #expect(throws: KeyboardServiceError.accessibility(.secureTextInput)) {
            try service.type("x")
        }
        #expect(
            poster.events == [.key(.leftCommand, [.command], true), .key(.leftCommand, [], false)]
        )
        #expect(resolver.resolveCount == 1)
    }

    // MARK: - Function Toolbar
    @Test func functionToolbarKeyAfterFnReleaseCarriesOnlyLatchedModifiers() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(target: keyboardServiceTarget()),
            eventPoster: poster
        )
        try service.toggleFunction()
        try service.toggleFunction()
        try service.toggleLatch(.leftCommand)
        try service.tap(KeyStroke(.f3, modifiers: service.modifierFlags))
        #expect(service.latchedModifiers.isEmpty)
        #expect(
            poster.events == [
                .key(.function, [.function], true), .key(.function, [], false),
                .key(.leftCommand, [.command], true),
                .key(.f3, [.command], true), .key(.f3, [.command], false),
                .key(.leftCommand, [], false),
            ]
        )
    }

    @Test func systemControlExecutionReportsFailuresAndConsumesModifiers() async throws {
        let performer = FakeSystemControlPerformer()
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(target: keyboardServiceTarget()),
            eventPoster: poster,
            systemControlPerformer: performer
        )
        try service.toggleLatch(.leftShift)
        try await service.perform(.volumeDown)
        #expect(performer.controls == [.volumeDown])
        #expect(service.latchedModifiers.isEmpty)
        #expect(poster.events == [.key(.leftShift, [.shift], true), .key(.leftShift, [], false)])
        performer.shouldFail = true
        await #expect(throws: KeyboardServiceError.deliveryFailed("System control unavailable")) {
            try await service.perform(.brightnessUp)
        }
        #expect(service.lastError == .deliveryFailed("System control unavailable"))
    }

    // MARK: - Modifier Posting Failures
    @Test func failedLatchDownDoesNotLatchAndCanBeRetried() throws {
        let poster = FakeKeyboardEventPoster()
        poster.failingKeyPostAttempts = [1]
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        #expect(throws: KeyboardServiceError.eventCreationFailed) {
            try service.toggleLatch(.leftShift)
        }
        #expect(service.lastError == .eventCreationFailed)
        #expect(service.latchedModifiers.isEmpty)
        #expect(poster.events.isEmpty)
        try service.toggleLatch(.leftShift)
        #expect(service.latchedModifiers == [.leftShift])
        #expect(service.lastError == nil)
        #expect(poster.events == [.key(.leftShift, [.shift], true)])
    }

    // MARK: - Latch Release Failure
    @Test func failedLatchUpRetainsLatchForExplicitRetry() throws {
        let poster = FakeKeyboardEventPoster()
        poster.failingKeyPostAttempts = [2]
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleLatch(.leftShift)
        #expect(throws: KeyboardServiceError.eventCreationFailed) {
            try service.toggleLatch(.leftShift)
        }
        #expect(service.lastError == .eventCreationFailed)
        #expect(service.latchedModifiers == [.leftShift])
        #expect(poster.events == [.key(.leftShift, [.shift], true)])
        try service.toggleLatch(.leftShift)
        #expect(service.latchedModifiers.isEmpty)
        #expect(service.lastError == nil)
        #expect(poster.events == [.key(.leftShift, [.shift], true), .key(.leftShift, [], false)])
    }

    // MARK: - Chord Failure Cleanup
    @Test func failedStrokeUpRetriesKeyUpAndReleasesTransferredModifier() throws {
        let poster = FakeKeyboardEventPoster()
        poster.failingKeyPostAttempts = [3]
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleLatch(.leftShift)
        #expect(throws: KeyboardServiceError.eventCreationFailed) {
            try service.tap(KeyStroke(.a, modifiers: [.shift]))
        }
        #expect(service.lastError == .eventCreationFailed)
        #expect(service.latchedModifiers.isEmpty)
        #expect(poster.keyPostAttempts == 5)
        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true),
                .key(.a, [.shift], true), .key(.a, [.shift], false),
                .key(.leftShift, [], false),
            ]
        )
        service.releaseAll()
        #expect(poster.keyPostAttempts == 5)
    }

    // MARK: - Cleanup Failure Recovery
    @Test func cleanupContinuesAfterOneReleaseFailsAndRetriesRemainingPostedModifier() throws {
        let poster = FakeKeyboardEventPoster()
        poster.failingKeyPostAttempts = [3]
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleLatch(.leftCommand)
        try service.toggleLatch(.leftShift)
        service.releaseAll()
        #expect(service.lastError == .eventCreationFailed)
        #expect(service.latchedModifiers.isEmpty)
        #expect(
            poster.events == [
                .key(.leftCommand, [.command], true),
                .key(.leftShift, [.command, .shift], true),
                .key(.leftCommand, [.shift], false),
            ]
        )
        service.releaseAll()
        #expect(poster.events.last == .key(.leftShift, [], false))
        #expect(poster.keyPostAttempts == 5)
        service.releaseAll()
        #expect(poster.keyPostAttempts == 5)
    }

    // MARK: - Prediction Delivery
    @Test func predictionUsesValidatedTargetWithoutResolvingAgain() throws {
        let target = keyboardServiceTarget(processIdentifier: 4321)
        let resolver = FakeKeyboardTargetResolver(target: keyboardServiceTarget())
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)
        try service.insertPrediction("llo ", into: target)
        #expect(resolver.resolveCount == 0)
        #expect(poster.events == [.text("llo ", 4321, .textElement)])
    }

    @Test func predictionReplacementUsesOnlyValidatedTarget() throws {
        let target = keyboardServiceTarget(processIdentifier: 4321)
        let resolver = FakeKeyboardTargetResolver(target: keyboardServiceTarget())
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)
        try service.insertPrediction("hello ", deletingBackward: 3, into: target)
        #expect(resolver.resolveCount == 0)
        #expect(poster.events == [.replacement(3, "hello ", 4321)])
    }

    // MARK: - Key Mapping
    @Test func keyRawValuesMatchMacVirtualKeyMap() {
        #expect(Key.a.cgKeyCode == 0x00)
        #expect(Key.`return`.cgKeyCode == 0x24)
        #expect(Key.keypadEnter.cgKeyCode == 0x4C)
        #expect(Key.f20.cgKeyCode == 0x5A)
        #expect(Key.jisKana.cgKeyCode == 0x68)
    }

    @Test func keyModifiersMapToCoreGraphicsFlags() {
        let modifiers: KeyModifiers = [
            .command,
            .shift,
            .option,
            .control,
            .function,
            .numericPad,
        ]

        let flags = modifiers.cgEventFlags

        #expect(flags.contains(.maskCommand))
        #expect(flags.contains(.maskShift))
        #expect(flags.contains(.maskAlternate))
        #expect(flags.contains(.maskControl))
        #expect(flags.contains(.maskSecondaryFn))
        #expect(flags.contains(.maskNumericPad))
    }

    @Test func keysAndModifiersRoundTripThroughJSON() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let modifiers: KeyModifiers = [.command, .shift, .option]
        let stroke = KeyStroke(.escape, modifiers: modifiers)

        let keyData = try encoder.encode(Key.escape)
        let modifierData = try encoder.encode(modifiers)
        let strokeData = try encoder.encode(stroke)
        let modifierKeyData = try encoder.encode(ModifierKey.leftShift)
        let behaviorData = try encoder.encode(KeyPressBehavior.oneShot)

        #expect(try decoder.decode(Key.self, from: keyData) == .escape)
        #expect(try decoder.decode(KeyModifiers.self, from: modifierData) == modifiers)
        #expect(try decoder.decode(KeyStroke.self, from: strokeData) == stroke)
        #expect(try decoder.decode(ModifierKey.self, from: modifierKeyData) == .leftShift)
        #expect(try decoder.decode(KeyPressBehavior.self, from: behaviorData) == .oneShot)
    }

    @Test func modifierKeyMapsToPhysicalKeyAndFlag() {
        #expect(ModifierKey.leftShift.key == .leftShift)
        #expect(ModifierKey.leftShift.modifiers == .shift)
        #expect(ModifierKey.rightCommand.key == .rightCommand)
        #expect(ModifierKey.rightCommand.modifiers == .command)
        #expect(ModifierKey.function.key == .function)
        #expect(ModifierKey.function.modifiers == .function)
    }

    @Test func keyActionsRoundTripThroughJSON() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let actions: [KeyAction] = [
            .none,
            .text("Hello"),
            .keyStroke(KeyStroke(.a, modifiers: [.shift])),
            .modifier(.leftShift),
            .cycleKeyboardLanguage,
        ]

        let data = try encoder.encode(actions)

        #expect(try decoder.decode([KeyAction].self, from: data) == actions)
    }

    // MARK: - Keystrokes
    @Test func tapPostsExactFlagsWithoutResolvingTarget() throws {
        let resolver = FakeKeyboardTargetResolver(target: keyboardServiceTarget(route: .window))
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        let receipt = try service.tap(KeyStroke(.a, modifiers: [.shift]))

        #expect(poster.events == [.key(.a, [.shift], true), .key(.a, [.shift], false)])
        #expect(receipt.method == .keyEvent)
        #expect(receipt.route == nil)
        #expect(receipt.processIdentifier == nil)
        #expect(resolver.resolveCount == 0)
    }

    @Test func shortcutTapPressesModifierKeysAroundTheKey() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )

        try service.tap(KeyStroke(.a, modifiers: [.command, .shift]))

        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true),
                .key(.leftCommand, [.command, .shift], true),
                .key(.a, [.command, .shift], true),
                .key(.a, [.command, .shift], false),
                .key(.leftCommand, [.shift], false),
                .key(.leftShift, [], false),
            ]
        )
    }

    // MARK: - Latched Modifiers
    @Test func latchFirstTogglePostsDownAndLatches() throws {
        let resolver = FakeKeyboardTargetResolver(target: keyboardServiceTarget(route: .window))
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        let receipt = try service.toggleLatch(.leftShift)

        #expect(resolver.resolveCount == 0)
        #expect(poster.events == [.key(.leftShift, [.shift], true)])
        #expect(service.latchedModifiers == [.leftShift])
        #expect(receipt.method == .modifierState)
    }

    @Test func latchAppliesToNextStrokeAndReleasesAfterIt() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )

        try service.toggleLatch(.leftShift)
        try service.tap(KeyStroke(.s, modifiers: [.shift]))

        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true),
                .key(.s, [.shift], true),
                .key(.s, [.shift], false),
                .key(.leftShift, [], false),
            ]
        )
        #expect(service.latchedModifiers.isEmpty)
    }

    @Test func releaseAllPostsUpAndClearsLatches() throws {
        let resolver = FakeKeyboardTargetResolver(target: keyboardServiceTarget(route: .window))
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        try service.toggleLatch(.leftShift)
        service.releaseAll()

        #expect(resolver.resolveCount == 0)
        #expect(poster.events == [.key(.leftShift, [.shift], true), .key(.leftShift, [], false)])
        #expect(service.latchedModifiers.isEmpty)
    }

    @Test func latchSecondTogglePostsUpAndUnlatches() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )

        try service.toggleLatch(.leftShift)
        try service.toggleLatch(.leftShift)

        #expect(poster.events == [.key(.leftShift, [.shift], true), .key(.leftShift, [], false)])
        #expect(service.latchedModifiers.isEmpty)
    }

    @Test func consumedLatchCanBeLatchedAgain() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleLatch(.leftShift)
        try service.tap(KeyStroke(.a, modifiers: [.shift]))
        try service.toggleLatch(.leftShift)

        #expect(service.latchedModifiers == [.leftShift])
        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true),
                .key(.a, [.shift], true), .key(.a, [.shift], false),
                .key(.leftShift, [], false),
                .key(.leftShift, [.shift], true),
            ]
        )
    }

    @Test func latchesStackAndReleaseInReverseOrderAfterTheStroke() throws {
        let resolver = FakeKeyboardTargetResolver(target: keyboardServiceTarget(route: .window))
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        try service.toggleLatch(.leftCommand)
        try service.toggleLatch(.leftShift)

        #expect(
            poster.events == [
                .key(.leftCommand, [.command], true),
                .key(.leftShift, [.command, .shift], true),
            ]
        )
        #expect(service.latchedModifiers == [.leftCommand, .leftShift])

        try service.tap(KeyStroke(.s, modifiers: [.command, .shift]))

        #expect(resolver.resolveCount == 0)
        #expect(
            Array(poster.events.suffix(4)) == [
                .key(.s, [.command, .shift], true),
                .key(.s, [.command, .shift], false),
                .key(.leftShift, [.command], false),
                .key(.leftCommand, [], false),
            ]
        )
        #expect(service.latchedModifiers.isEmpty)
    }

    @Test func latchNotCarriedByTheStrokeIsReleasedBeforeIt() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleLatch(.leftShift)
        try service.tap(KeyStroke(.a))

        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true), .key(.leftShift, [], false),
                .key(.a, [], true), .key(.a, [], false),
            ]
        )
        #expect(service.latchedModifiers.isEmpty)
    }

    @Test func globalHotkeyDoesNotRequireFocusedApplicationResolution() throws {
        let resolver = FakeKeyboardTargetResolver(
            error: AccessibilityFocusError.focusedApplicationUnavailable
        )
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        try service.toggleLatch(.leftCommand)
        try service.toggleLatch(.leftShift)
        try service.tap(KeyStroke(.s, modifiers: [.command, .shift]))

        #expect(resolver.resolveCount == 0)
        #expect(poster.events.count == 6)
    }

    // MARK: - Modifier Taps
    @Test func modifierTapPressesAndReleasesWithoutLatching() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.tapModifier(.leftOption)
        #expect(
            poster.events == [.key(.leftOption, [.option], true), .key(.leftOption, [], false)]
        )
        #expect(service.latchedModifiers.isEmpty)

        try service.toggleLatch(.leftOption)
        try service.tapModifier(.leftOption)
        #expect(service.latchedModifiers == [.leftOption])
        #expect(poster.events.count == 3)
    }

    // MARK: - Text Input
    @Test func typePostsTextToFocusedTarget() throws {
        let target = keyboardServiceTarget(route: .textElement)
        let resolver = FakeKeyboardTargetResolver(target: target)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        let receipt = try service.type("Hello")

        #expect(resolver.resolveCount == 1)
        #expect(poster.events == [.text("Hello", target.processIdentifier, .textElement)])
        #expect(receipt.method == .textEvent)
        #expect(receipt.route == .textElement)
        #expect(receipt.processIdentifier == target.processIdentifier)
        #expect(service.lastError == nil)
        #expect(service.lastReceipt == receipt)
    }

    @Test func typeConsumesLatchedModifiersAfterTheText() throws {
        let target = keyboardServiceTarget()
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(target: target),
            eventPoster: poster
        )
        try service.toggleLatch(.leftShift)
        try service.type("é")
        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true),
                .text("é", target.processIdentifier, .textElement),
                .key(.leftShift, [], false),
            ]
        )
        #expect(service.latchedModifiers.isEmpty)
    }

    @Test func typeEmptyTextDoesNotResolveOrPost() throws {
        let resolver = FakeKeyboardTargetResolver(target: keyboardServiceTarget())
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        let receipt = try service.type("")

        #expect(resolver.resolveCount == 0)
        #expect(poster.events.isEmpty)
        #expect(receipt.method == .noOperation)
    }

    @Test func typeRecordsResolverErrors() {
        let resolver = FakeKeyboardTargetResolver(
            error: AccessibilityFocusError.accessibilityNotAuthorized
        )
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        #expect(throws: KeyboardServiceError.self) {
            try service.type("Hello")
        }

        #expect(poster.events.isEmpty)
        #expect(service.lastError == .accessibility(.accessibilityNotAuthorized))
    }

    // MARK: - Physical Modifiers
    @Test func physicallyHeldModifierIsNotPressedAgain() throws {
        let physical = PhysicalKeyboardState(
            readHardware: {
                PhysicalKeyboardSnapshot(pressedKeys: [.rightOption], modifiers: [.rightOption])
            },
            canObserve: { true }
        )
        physical.refresh()
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster,
            physicalKeyboard: physical
        )
        try service.toggleLatch(.leftOption)
        try service.tap(KeyStroke(.two, modifiers: [.option]))
        #expect(poster.events == [.key(.two, [.option], true), .key(.two, [.option], false)])
        #expect(service.latchedModifiers.isEmpty)
        #expect(service.effectiveModifiers == [.rightOption])
    }

    @Test func syntheticModifierReleasePreservesPhysicallyHeldFlags() throws {
        let physical = PhysicalKeyboardState(
            readHardware: {
                PhysicalKeyboardSnapshot(pressedKeys: [.leftOption], modifiers: [.leftOption])
            },
            canObserve: { true }
        )
        physical.refresh()
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster,
            physicalKeyboard: physical
        )
        try service.toggleLatch(.rightShift)
        try service.tap(KeyStroke(.two, modifiers: [.option, .shift]))
        #expect(
            poster.events == [
                .key(.rightShift, [.option, .shift], true),
                .key(.two, [.option, .shift], true), .key(.two, [.option, .shift], false),
                .key(.rightShift, [.option], false),
            ]
        )
    }

    @Test func tapDoesNotAddPhysicalCapsLockToResolvedStroke() throws {
        let physical = PhysicalKeyboardState(
            readHardware: { PhysicalKeyboardSnapshot(isCapsLockEnabled: true) },
            canObserve: { true }
        )
        physical.refresh()
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster,
            physicalKeyboard: physical
        )
        #expect(service.isCapsLockEnabled)
        try service.tap(KeyStroke(.a))
        #expect(poster.events == [.key(.a, [], true), .key(.a, [], false)])
    }

    // MARK: - Shortcut Modifier Keys
    @Test func shortcutStrokePressesModifierKeysLikeAccessibilityKeyboard() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )

        try service.tap(KeyStroke(.equal, modifiers: [.control, .command]))

        #expect(
            poster.events == [
                .key(.leftControl, [.control], true),
                .key(.leftCommand, [.control, .command], true),
                .key(.equal, [.control, .command], true),
                .key(.equal, [.control, .command], false),
                .key(.leftCommand, [.control], false),
                .key(.leftControl, [], false),
            ]
        )
    }

    @Test func shortcutStrokeDoesNotRepressLatchedModifier() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )

        try service.toggleLatch(.rightCommand)
        try service.tap(KeyStroke(.equal, modifiers: [.control, .command]))

        #expect(
            poster.events == [
                .key(.rightCommand, [.command], true),
                .key(.leftControl, [.command, .control], true),
                .key(.equal, [.control, .command], true),
                .key(.equal, [.control, .command], false),
                .key(.leftControl, [.command], false),
                .key(.rightCommand, [], false),
            ]
        )
    }

    @Test func shiftedCharacterStrokeKeepsFlagsOnlyDelivery() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )

        try service.tap(KeyStroke(.a, modifiers: [.shift]))

        #expect(poster.events == [.key(.a, [.shift], true), .key(.a, [.shift], false)])
    }
}
