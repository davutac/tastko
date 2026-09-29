import CoreGraphics
import Foundation
import Testing

@testable import Tastko

// MARK: - Function Key
extension KeyboardServiceTests {
    // MARK: - Fn Toggle
    @Test func functionTogglePostsImmediatelyAndHoldsUntilNextToggle() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )

        try service.toggleFunction()
        #expect(poster.events == [.key(.function, [.function], true)])
        #expect(service.heldModifiers == [.function])
        #expect(service.latchedModifiers.isEmpty)

        try service.toggleFunction()
        #expect(poster.events == [.key(.function, [.function], true), .key(.function, [], false)])
        #expect(service.heldModifiers.isEmpty)
    }

    @Test func latchPostsImmediately() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )

        try service.toggleLatch(.leftCommand)

        #expect(poster.events == [.key(.leftCommand, [.command], true)])
    }

    // MARK: - Fn Hardware Reconciliation
    @Test func releasingVirtualFnClearsTheFlagAndAllowsAnotherPressDespiteStaleKeycode() throws {
        let hardware = FakeHardwareState()
        let physical = PhysicalKeyboardState(
            readHardware: {
                PhysicalKeyboardState.hardwareSnapshot(
                    pressedKeys: hardware.snapshot.pressedKeys,
                    flags: hardware.snapshot.modifierFlags.cgEventFlags
                )
            },
            canObserve: { true }
        )
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster,
            physicalKeyboard: physical
        )
        try service.toggleFunction()
        // Reproduce the live mismatch after the app's Fn click: keycode down, flag off.
        hardware.snapshot = PhysicalKeyboardSnapshot(pressedKeys: [.function])
        physical.refresh()
        try service.toggleFunction()
        #expect(service.effectiveModifiers.contains(.function) == false)
        try service.toggleFunction()
        try service.toggleFunction()
        #expect(
            poster.events == [
                .key(.function, [.function], true), .key(.function, [], false),
                .key(.function, [.function], true), .key(.function, [], false),
            ]
        )
    }

    // MARK: - Held Fn
    @Test func functionHoldLastsAcrossStrokesUntilToggledOff() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleLatch(.leftCommand)
        try service.toggleFunction()
        #expect(service.heldModifiers == [.function])
        #expect(service.effectiveModifiers == [.leftCommand, .function])
        #expect(
            poster.events == [
                .key(.leftCommand, [.command], true),
                .key(.function, [.command, .function], true),
            ]
        )

        try service.tap(KeyStroke(.a, modifiers: [.command, .function]))
        #expect(service.heldModifiers == [.function])
        #expect(service.latchedModifiers.isEmpty)
        #expect(
            poster.events == [
                .key(.leftCommand, [.command], true),
                .key(.function, [.command, .function], true),
                .key(.a, [.command, .function], true), .key(.a, [.command, .function], false),
                .key(.leftCommand, [.function], false),
            ]
        )
        try service.toggleFunction()
        #expect(poster.events.last == .key(.function, [], false))
        #expect(service.heldModifiers.isEmpty)
    }

    // MARK: - Fn Latch Routing
    @Test func latchingFunctionTogglesTheSameHold() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        let receipt = try service.toggleLatch(.function)
        #expect(receipt.method == .keyEvent)
        #expect(service.latchedModifiers.isEmpty)
        #expect(service.heldModifiers == [.function])
        try service.tapModifier(.function)
        #expect(
            poster.events == [
                .key(.function, [.function], true), .key(.function, [], false),
            ]
        )
        #expect(service.latchedModifiers.isEmpty)
        #expect(service.heldModifiers.isEmpty)
    }

    // MARK: - Toggle Cleanup
    @Test func functionToggleSurvivesTypingAndCanRestartAfterCleanup() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleFunction()
        try service.tap(KeyStroke(.a, modifiers: [.function]))
        #expect(service.heldModifiers == [.function])
        service.releaseAll()
        #expect(service.heldModifiers.isEmpty)
        try service.toggleFunction()
        try service.toggleFunction()
        #expect(service.heldModifiers.isEmpty)
        #expect(
            poster.events == [
                .key(.function, [.function], true),
                .key(.a, [.function], true), .key(.a, [.function], false),
                .key(.function, [], false),
                .key(.function, [.function], true), .key(.function, [], false),
            ]
        )
    }

    // MARK: - Physical Fn
    @Test func physicallyHeldFunctionIsNeitherDuplicatedNorReleasedByVirtualInput() throws {
        let physical = PhysicalKeyboardState(
            readHardware: {
                PhysicalKeyboardSnapshot(pressedKeys: [.function], modifiers: [.function])
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
        try service.toggleFunction()
        try service.toggleLatch(.function)
        service.releaseAll()
        #expect(poster.events.isEmpty)
        #expect(service.latchedModifiers.isEmpty)
        #expect(service.heldModifiers == [.function])
        try service.tap(KeyStroke(.a, modifiers: [.function]))
        #expect(poster.events == [.key(.a, [.function], true), .key(.a, [.function], false)])
    }

    // MARK: - Fn Lock Transition
    @Test func lockTransitionsReleaseTheFunctionHold() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster,
            canPostEvents: { true }
        )
        try service.toggleFunction()
        service.setScreenLocked(true, allowsInput: true)
        #expect(service.heldModifiers.isEmpty)
        #expect(poster.events == [.key(.function, [.function], true), .key(.function, [], false)])
        try service.toggleFunction()
        #expect(service.heldModifiers == [.function])
        service.setScreenLocked(false, allowsInput: false)
        #expect(service.heldModifiers.isEmpty)
        #expect(
            poster.events == [
                .key(.function, [.function], true), .key(.function, [], false),
                .key(.function, [.function], true), .key(.function, [], false),
            ]
        )
    }

    // MARK: - Modifier Cleanup
    @Test func cleanupReleasesLatchesBeforeFnAndOnlyOnce() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleLatch(.leftCommand)
        try service.toggleLatch(.leftShift)
        try service.toggleFunction()
        service.releaseAll()
        #expect(service.latchedModifiers.isEmpty)
        #expect(service.heldModifiers.isEmpty)
        #expect(
            poster.events == [
                .key(.leftCommand, [.command], true),
                .key(.leftShift, [.command, .shift], true),
                .key(.function, [.command, .shift, .function], true),
                .key(.leftShift, [.command, .function], false),
                .key(.leftCommand, [.function], false),
                .key(.function, [], false),
            ]
        )
        service.releaseAll()
        #expect(poster.events.count == 6)
    }

    // MARK: - Fn Caps Lock Flags
    @Test func functionTransitionsPreservePhysicalCapsLockAndOtherHeldFlags() throws {
        let physical = PhysicalKeyboardState(
            readHardware: {
                PhysicalKeyboardSnapshot(
                    pressedKeys: [.rightOption],
                    modifiers: [.rightOption],
                    isCapsLockEnabled: true
                )
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
        try service.toggleFunction()
        try service.toggleFunction()
        #expect(
            poster.events == [
                .key(.function, [.function, .option, .capsLock], true),
                .key(.function, [.option, .capsLock], false),
            ]
        )
        #expect(service.effectiveModifiers == [.rightOption])
        #expect(service.isCapsLockEnabled)
    }

    // MARK: - Fn Down Failure
    @Test func failedFunctionDownDoesNotCreateAHold() throws {
        let poster = FakeKeyboardEventPoster()
        poster.failingKeyPostAttempts = [1]
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        #expect(throws: KeyboardServiceError.eventCreationFailed) {
            try service.toggleFunction()
        }
        #expect(service.lastError == .eventCreationFailed)
        #expect(service.heldModifiers.isEmpty)
        #expect(poster.events.isEmpty)
        try service.toggleFunction()
        try service.toggleFunction()
        #expect(service.lastError == nil)
        #expect(poster.events == [.key(.function, [.function], true), .key(.function, [], false)])
    }

    // MARK: - Fn Up Failure
    @Test func failedFunctionUpKeepsTheHoldForRetry() throws {
        let poster = FakeKeyboardEventPoster()
        poster.failingKeyPostAttempts = [2]
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleFunction()
        #expect(throws: KeyboardServiceError.eventCreationFailed) {
            try service.toggleFunction()
        }
        #expect(service.lastError == .eventCreationFailed)
        #expect(service.heldModifiers == [.function])
        #expect(poster.events == [.key(.function, [.function], true)])
        try service.toggleFunction()
        #expect(service.heldModifiers.isEmpty)
        #expect(service.lastError == nil)
        #expect(poster.events == [.key(.function, [.function], true), .key(.function, [], false)])
    }
}
