import ApplicationServices
import CoreGraphics
import Foundation
import Testing

@testable import Tastko

// MARK: - KeyboardServiceTests
@MainActor
struct KeyboardServiceTests {
    // MARK: - Lock-Screen Input
    @Test func lockedInputUsesSystemFocusWithoutReadingFieldsOrRetainingKeyReceipts() async throws {
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
        try await service.press(.x)
        try await service.press(.delete)
        let receipt = try await service.type("ä")
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

    @Test func lockedModifiersStillProducePairedChordEvents() async throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(
                error: AccessibilityFocusError.secureTextInput
            ),
            eventPoster: poster,
            canPostEvents: { true }
        )
        service.setScreenLocked(true, allowsInput: true)
        try service.toggleOneShotModifier(.leftShift)
        try await service.perform(.keyStroke(KeyStroke(.x)))
        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true),
                .key(.x, [.shift], true), .key(.x, [.shift], false),
                .key(.leftShift, [], false),
            ]
        )
        #expect(service.activeOneShotModifiers.isEmpty)
    }

    @Test func lockedPermissionDenialPostsNothingAndDoesNotResolveAnyTarget() async {
        let resolver = FakeKeyboardTargetResolver(error: AccessibilityFocusError.secureTextInput)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: resolver,
            eventPoster: poster,
            canPostEvents: { false }
        )
        service.setScreenLocked(true, allowsInput: true)
        await #expect(throws: KeyboardServiceError.self) { try await service.type("x") }
        await #expect(throws: KeyboardServiceError.self) { try await service.press(.x) }
        #expect(throws: KeyboardServiceError.accessibility(.accessibilityNotAuthorized)) {
            try service.toggleOneShotModifier(.leftShift)
        }
        #expect(throws: KeyboardServiceError.accessibility(.accessibilityNotAuthorized)) {
            try service.beginFunctionPress()
        }
        #expect(service.activeOneShotModifiers.isEmpty)
        #expect(service.heldModifiers.isEmpty)
        #expect(poster.events.isEmpty)
        #expect(resolver.resolveCount == 0)
    }

    @Test func lockedModeRejectsQueuedPredictionsAndUnlockRestoresSecureTargetExclusion()
        async throws
    {
        let resolver = FakeKeyboardTargetResolver(error: AccessibilityFocusError.secureTextInput)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: resolver,
            eventPoster: poster,
            canPostEvents: { true }
        )
        try service.toggleOneShotModifier(.leftCommand)
        let beforeLock = service.inputSession
        service.setScreenLocked(true, allowsInput: true)
        #expect(service.inputSession != beforeLock)
        #expect(service.activeOneShotModifiers.isEmpty)
        #expect(throws: KeyboardServiceError.self) {
            try service.type("old suggestion", toValidatedTarget: keyboardServiceTarget())
        }
        let lockedSession = service.inputSession
        service.setScreenLocked(false, allowsInput: false)
        #expect(service.inputSession != lockedSession)
        await #expect(throws: KeyboardServiceError.accessibility(.secureTextInput)) {
            try await service.type("x")
        }
        #expect(
            poster.events == [.key(.leftCommand, [.command], true), .key(.leftCommand, [], false)]
        )
        #expect(resolver.resolveCount == 1)
    }

    // MARK: - Function Toolbar
    @Test func functionToolbarAfterFnReleaseConsumesOnlyStickyModifiers()
        async throws
    {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(target: keyboardServiceTarget()),
            eventPoster: poster
        )
        try service.toggleFunctionKey()
        try service.toggleFunctionKey()
        try service.toggleOneShotModifier(.leftCommand)
        try await service.pressFunctionToolbarKey(.f3)
        #expect(service.activeOneShotModifiers.isEmpty)
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
        try service.toggleOneShotModifier(.leftShift)
        try await service.performSystemControl(.volumeDown)
        #expect(performer.controls == [.volumeDown])
        #expect(service.activeOneShotModifiers.isEmpty)
        #expect(poster.events == [.key(.leftShift, [.shift], true), .key(.leftShift, [], false)])
        performer.shouldFail = true
        await #expect(throws: KeyboardServiceError.deliveryFailed("System control unavailable")) {
            try await service.performSystemControl(.brightnessUp)
        }
        #expect(service.lastError == .deliveryFailed("System control unavailable"))
    }

    // MARK: - Modifier Posting Failures
    @Test func failedStickyModifierDownDoesNotLatchAndCanBeRetried() throws {
        let poster = FakeKeyboardEventPoster()
        poster.failingKeyPostAttempts = [1]
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        #expect(throws: KeyboardServiceError.eventCreationFailed) {
            try service.toggleOneShotModifier(.leftShift)
        }
        #expect(service.lastError == .eventCreationFailed)
        #expect(service.activeOneShotModifiers.isEmpty)
        #expect(poster.events.isEmpty)
        try service.toggleOneShotModifier(.leftShift)
        #expect(service.activeOneShotModifiers == [.leftShift])
        #expect(service.lastError == nil)
        #expect(poster.events == [.key(.leftShift, [.shift], true)])
    }

    // MARK: - Sticky Release Failure
    @Test func failedStickyModifierUpRetainsLatchForExplicitRetry() throws {
        let poster = FakeKeyboardEventPoster()
        poster.failingKeyPostAttempts = [2]
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleOneShotModifier(.leftShift)
        #expect(throws: KeyboardServiceError.eventCreationFailed) {
            try service.toggleOneShotModifier(.leftShift)
        }
        #expect(service.lastError == .eventCreationFailed)
        #expect(service.activeOneShotModifiers == [.leftShift])
        #expect(poster.events == [.key(.leftShift, [.shift], true)])
        try service.toggleOneShotModifier(.leftShift)
        #expect(service.activeOneShotModifiers.isEmpty)
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
        try service.toggleOneShotModifier(.leftShift)
        let modifiers = service.consumeActiveOneShotModifiers()
        #expect(throws: KeyboardServiceError.eventCreationFailed) {
            try service.press(KeyStroke(.a), latchedModifiers: modifiers)
        }
        #expect(service.lastError == .eventCreationFailed)
        #expect(service.activeOneShotModifiers.isEmpty)
        #expect(poster.keyPostAttempts == 5)
        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true),
                .key(.a, [.shift], true), .key(.a, [.shift], false),
                .key(.leftShift, [], false),
            ]
        )
        service.releaseAllModifiers()
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
        try service.toggleOneShotModifier(.leftCommand)
        try service.toggleOneShotModifier(.leftShift)
        service.releaseAllModifiers()
        #expect(service.lastError == .eventCreationFailed)
        #expect(service.activeOneShotModifiers.isEmpty)
        #expect(
            poster.events == [
                .key(.leftCommand, [.command], true),
                .key(.leftShift, [.command, .shift], true),
                .key(.leftCommand, [.shift], false),
            ]
        )
        service.releaseAllModifiers()
        #expect(poster.events.last == .key(.leftShift, [], false))
        #expect(poster.keyPostAttempts == 5)
        service.releaseAllModifiers()
        #expect(poster.keyPostAttempts == 5)
    }

    // MARK: - Prediction Delivery
    @Test func predictionUsesValidatedTargetWithoutResolvingAgain() throws {
        let target = keyboardServiceTarget(processIdentifier: 4321)
        let resolver = FakeKeyboardTargetResolver(target: keyboardServiceTarget())
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)
        try service.type("llo ", toValidatedTarget: target)
        #expect(resolver.resolveCount == 0)
        #expect(poster.events == [.text("llo ", 4321, .textElement)])
    }

    // MARK: - Keys
    @Test func predictionReplacementUsesOnlyValidatedTarget() throws {
        let target = keyboardServiceTarget(processIdentifier: 4321)
        let resolver = FakeKeyboardTargetResolver(target: keyboardServiceTarget())
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)
        try service.type("hello ", deletingBackward: 3, toValidatedTarget: target)
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

    // MARK: - Key Actions
    @Test func performNoneRecordsNoOperationWithoutResolvingTarget() async throws {
        let resolver = FakeKeyboardTargetResolver(target: keyboardServiceTarget())
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        let receipt = try await service.perform(.none)

        #expect(resolver.resolveCount == 0)
        #expect(poster.events.isEmpty)
        #expect(receipt.method == .noOperation)
        #expect(receipt.summary == "key action none")
        #expect(service.lastReceipt == receipt)
    }

    @Test func performTextRoutesThroughTextInput() async throws {
        let target = keyboardServiceTarget(route: .textElement)
        let resolver = FakeKeyboardTargetResolver(target: target)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        let receipt = try await service.perform(.text("Hello"))

        #expect(resolver.resolveCount == 1)
        #expect(poster.events == [.text("Hello", target.processIdentifier, .textElement)])
        #expect(receipt.method == .textEvent)
    }

    @Test func performKeyStrokeRoutesThroughKeystrokeInput() async throws {
        let target = keyboardServiceTarget(route: .window)
        let resolver = FakeKeyboardTargetResolver(target: target)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        let receipt = try await service.perform(.keyStroke(KeyStroke(.a, modifiers: [.shift])))

        #expect(
            poster.events == [
                .key(.a, [.shift], true),
                .key(.a, [.shift], false),
            ]
        )
        #expect(receipt.method == .keyEvent)
        #expect(receipt.route == nil)
        #expect(receipt.processIdentifier == nil)
        #expect(resolver.resolveCount == 0)
    }

    @Test func oneShotModifierFirstClickPostsDownAndLatches() async throws {
        let target = keyboardServiceTarget(route: .window)
        let resolver = FakeKeyboardTargetResolver(target: target)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        let receipt = try await service.perform(.modifier(.leftShift), behavior: .oneShot)

        #expect(resolver.resolveCount == 0)
        #expect(poster.events == [.key(.leftShift, [.shift], true)])
        #expect(service.activeOneShotModifiers == [.leftShift])
        #expect(receipt.method == .modifierState)
    }

    @Test func oneShotModifierAppliesToNextKeyStrokeAndReleases() async throws {
        let target = keyboardServiceTarget(route: .window)
        let resolver = FakeKeyboardTargetResolver(target: target)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        try await service.perform(.modifier(.leftShift), behavior: .oneShot)
        try await service.perform(.keyStroke(KeyStroke(.s)))

        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true),
                .key(.s, [.shift], true),
                .key(.s, [.shift], false),
                .key(.leftShift, [], false),
            ]
        )
        #expect(service.activeOneShotModifiers.isEmpty)
    }

    @Test func directPressUsesActiveOneShotModifierWithoutReleasingIt() async throws {
        let target = keyboardServiceTarget(route: .window)
        let resolver = FakeKeyboardTargetResolver(target: target)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        try await service.perform(.modifier(.leftShift), behavior: .oneShot)
        try await service.press(.a)

        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true),
                .key(.a, [.shift], true),
                .key(.a, [.shift], false),
            ]
        )
        #expect(service.activeOneShotModifiers == [.leftShift])
        service.releaseAllModifiers()
        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true),
                .key(.a, [.shift], true), .key(.a, [.shift], false),
                .key(.leftShift, [], false),
            ]
        )
        #expect(service.activeOneShotModifiers.isEmpty)
    }

    @Test func releaseAllModifiersPostsUpAndClearsVirtualState() async throws {
        let target = keyboardServiceTarget(route: .window)
        let resolver = FakeKeyboardTargetResolver(target: target)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        try await service.perform(.modifier(.leftShift), behavior: .oneShot)
        service.releaseAllModifiers()

        #expect(resolver.resolveCount == 0)
        #expect(poster.events == [.key(.leftShift, [.shift], true), .key(.leftShift, [], false)])
        #expect(service.activeOneShotModifiers.isEmpty)
    }

    @Test func activeOneShotModifierSecondClickPostsUpAndUnlatches() async throws {
        let target = keyboardServiceTarget(route: .window)
        let resolver = FakeKeyboardTargetResolver(target: target)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        try await service.perform(.modifier(.leftShift), behavior: .oneShot)
        try await service.perform(.modifier(.leftShift), behavior: .oneShot)

        #expect(resolver.resolveCount == 0)
        #expect(poster.events == [.key(.leftShift, [.shift], true), .key(.leftShift, [], false)])
        #expect(service.activeOneShotModifiers.isEmpty)
    }

    // MARK: - Latch Transfer
    @Test func consumingLatchKeepsModifierDownUntilSynchronousStrokeCompletes() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleOneShotModifier(.leftShift)

        let consumedModifiers = service.consumeActiveOneShotModifiers()

        #expect(consumedModifiers == [.leftShift])
        #expect(service.activeOneShotModifiers.isEmpty)
        #expect(poster.events == [.key(.leftShift, [.shift], true)])

        try service.press(KeyStroke(.a), latchedModifiers: consumedModifiers)

        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true),
                .key(.a, [.shift], true), .key(.a, [.shift], false),
                .key(.leftShift, [], false),
            ]
        )
        try service.toggleOneShotModifier(.leftShift)
        #expect(service.activeOneShotModifiers == [.leftShift])
        #expect(poster.events.last == .key(.leftShift, [.shift], true))
    }

    @Test func multipleOneShotModifiersStackAndReleaseAfterNextKeyStroke() async throws {
        let target = keyboardServiceTarget(route: .window)
        let resolver = FakeKeyboardTargetResolver(target: target)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        try await service.perform(.modifier(.leftShift), behavior: .oneShot)
        try await service.perform(.modifier(.leftCommand), behavior: .oneShot)
        try await service.perform(.keyStroke(KeyStroke(.s)))

        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true),
                .key(
                    .leftCommand,
                    [.command, .shift],
                    true
                ),
                .key(.s, [.command, .shift], true),
                .key(.s, [.command, .shift], false),
                .key(.leftCommand, [.shift], false),
                .key(.leftShift, [], false),
            ]
        )
        #expect(service.activeOneShotModifiers.isEmpty)
    }

    @Test func stickyModifierChordPostsDownImmediatelyAndReleasesInReverseOrder() async throws {
        let target = keyboardServiceTarget(route: .window)
        let resolver = FakeKeyboardTargetResolver(target: target)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        try await service.perform(.modifier(.leftCommand), behavior: .oneShot)
        try await service.perform(.modifier(.leftShift), behavior: .oneShot)

        #expect(resolver.resolveCount == 0)
        #expect(
            poster.events == [
                .key(.leftCommand, [.command], true),
                .key(.leftShift, [.command, .shift], true),
            ]
        )
        #expect(service.activeOneShotModifiers == [.leftCommand, .leftShift])

        try await service.perform(.keyStroke(KeyStroke(.s)))

        #expect(resolver.resolveCount == 0)
        #expect(
            poster.events == [
                .key(.leftCommand, [.command], true),
                .key(
                    .leftShift,
                    [.command, .shift],
                    true
                ),
                .key(.s, [.command, .shift], true),
                .key(.s, [.command, .shift], false),
                .key(.leftShift, [.command], false),
                .key(.leftCommand, [], false),
            ]
        )
        #expect(service.activeOneShotModifiers.isEmpty)
    }

    @Test func globalHotkeyDoesNotRequireFocusedApplicationResolution() async throws {
        let resolver = FakeKeyboardTargetResolver(
            error: AccessibilityFocusError.focusedApplicationUnavailable
        )
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        try await service.perform(.modifier(.leftCommand), behavior: .oneShot)
        try await service.perform(.modifier(.leftShift), behavior: .oneShot)
        try await service.perform(.keyStroke(KeyStroke(.s)))

        #expect(resolver.resolveCount == 0)
        #expect(poster.events.count == 6)
    }

    // MARK: - Text Input
    @Test func typePostsTextToFocusedTarget() async throws {
        let target = keyboardServiceTarget(route: .textElement)
        let resolver = FakeKeyboardTargetResolver(target: target)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        let receipt = try await service.type("Hello")

        #expect(resolver.resolveCount == 1)
        #expect(poster.events == [.text("Hello", target.processIdentifier, .textElement)])
        #expect(receipt.method == .textEvent)
        #expect(receipt.route == .textElement)
        #expect(receipt.processIdentifier == target.processIdentifier)
        #expect(service.lastError == nil)
        #expect(service.lastReceipt == receipt)
    }

    @Test func typeEmptyTextDoesNotResolveOrPost() async throws {
        let resolver = FakeKeyboardTargetResolver(target: keyboardServiceTarget())
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        let receipt = try await service.type("")

        #expect(resolver.resolveCount == 0)
        #expect(poster.events.isEmpty)
        #expect(receipt.method == .noOperation)
    }

    @Test func typeRecordsResolverErrors() async {
        let resolver = FakeKeyboardTargetResolver(
            error: AccessibilityFocusError.accessibilityNotAuthorized
        )
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        await #expect(throws: KeyboardServiceError.self) {
            try await service.type("Hello")
        }

        #expect(poster.events.isEmpty)
        #expect(service.lastError == .accessibility(.accessibilityNotAuthorized))
    }

    // MARK: - Physical Modifiers
    @Test func physicalModifiersAreIncludedWithoutSyntheticModifierTransitions() async throws {
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
        try service.toggleOneShotModifier(.leftOption)
        try await service.perform(.keyStroke(KeyStroke(.two)))
        #expect(poster.events == [.key(.two, [.option], true), .key(.two, [.option], false)])
        #expect(service.activeOneShotModifiers.isEmpty)
        #expect(service.effectiveModifiers == [.rightOption])
    }

    @Test func syntheticModifierReleasePreservesPhysicallyHeldFlags() async throws {
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
        try service.toggleOneShotModifier(.rightShift)
        try await service.perform(.keyStroke(KeyStroke(.two)))
        #expect(
            poster.events == [
                .key(.rightShift, [.option, .shift], true),
                .key(.two, [.option, .shift], true), .key(.two, [.option, .shift], false),
                .key(.rightShift, [.option], false),
            ]
        )
    }

    @Test func resolvedCapsLockRightClickDoesNotReapplyPhysicalCapsLock() async throws {
        let physical = PhysicalKeyboardState(
            readHardware: {
                PhysicalKeyboardSnapshot(isCapsLockEnabled: true)
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
        #expect(service.effectiveCapsLockEnabled)
        try service.press(
            KeyStroke(.a),
            latchedModifiers: [],
            modifiersAreResolved: true
        )
        #expect(poster.events == [.key(.a, [], true), .key(.a, [], false)])
    }

    // MARK: - Keystroke Input
    @Test func pressPostsKeyDownAndKeyUp() async throws {
        let target = keyboardServiceTarget(route: .window)
        let resolver = FakeKeyboardTargetResolver(target: target)
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(targetResolver: resolver, eventPoster: poster)

        let receipt = try await service.press(.a, modifiers: [.command, .shift])

        #expect(
            poster.events == [
                .key(.a, [.command, .shift], true),
                .key(.a, [.command, .shift], false),
            ]
        )
        #expect(receipt.method == .keyEvent)
        #expect(receipt.route == nil)
        #expect(resolver.resolveCount == 0)
    }
}
