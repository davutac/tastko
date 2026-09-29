import CoreGraphics
import Foundation
import Testing

@testable import Tastko

// MARK: - Held Keys
extension KeyboardServiceTests {
    // MARK: - Held Key Lifecycle
    @Test func heldKeyWaitsForReleaseAndRepeatsNeverPostPrematureKeyUp() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        let press = try service.beginPress(KeyStroke(.delete))
        #expect(poster.events == [.key(.delete, [], true)])

        try service.repeatPress(press)
        try service.repeatPress(press)
        #expect(
            poster.events == [
                .key(.delete, [], true), .keyRepeat(.delete, []), .keyRepeat(.delete, []),
            ]
        )

        try service.endPress(press)
        #expect(
            poster.events == [
                .key(.delete, [], true), .keyRepeat(.delete, []), .keyRepeat(.delete, []),
                .key(.delete, [], false),
            ]
        )
        try service.repeatPress(press)
        try service.endPress(press)
        #expect(poster.events.count == 4)
    }

    // MARK: - Held Key Latches
    @Test func transferredLatchesStayDownThroughRepeatsAndReleaseAfterKeyUp() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleLatch(.leftCommand)
        try service.toggleLatch(.leftShift)
        let press = try service.beginPress(KeyStroke(.a, modifiers: [.command, .shift]))
        try service.repeatPress(press)
        try service.repeatPress(press)
        #expect(service.latchedModifiers.isEmpty)
        #expect(
            poster.events == [
                .key(.leftCommand, [.command], true),
                .key(.leftShift, [.command, .shift], true),
                .key(.a, [.command, .shift], true),
                .keyRepeat(.a, [.command, .shift]), .keyRepeat(.a, [.command, .shift]),
            ]
        )

        try service.endPress(press)
        #expect(
            Array(poster.events.suffix(3)) == [
                .key(.a, [.command, .shift], false),
                .key(.leftShift, [.command], false), .key(.leftCommand, [], false),
            ]
        )
        service.releaseAll()
        #expect(poster.events.count == 8)
    }

    // MARK: - Held Key Shortcut Modifiers
    @Test func heldShortcutStrokePressesModifierKeysUntilRelease() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )

        let press = try service.beginPress(KeyStroke(.equal, modifiers: [.control, .command]))
        try service.endPress(press)

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

    // MARK: - Held Key Cleanup
    @Test(arguments: [false, true])
    func cleanupReleasesKeyBeforeModifiersAndStalePressCannotAffectNewPress(
        lockTransition: Bool
    ) throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster,
            canPostEvents: { true }
        )
        try service.toggleLatch(.leftShift)
        let oldPress = try service.beginPress(KeyStroke(.a, modifiers: [.shift]))
        try service.repeatPress(oldPress)
        let session = service.inputSession
        if lockTransition {
            service.setScreenLocked(true, allowsInput: true)
        }
        else {
            service.releaseAll()
        }
        #expect(service.inputSession != session)
        #expect(service.latchedModifiers.isEmpty)
        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true), .key(.a, [.shift], true),
                .keyRepeat(.a, [.shift]), .key(.a, [.shift], false),
                .key(.leftShift, [], false),
            ]
        )
        let newPress = try service.beginPress(KeyStroke(.a))
        #expect(newPress != oldPress)
        try service.repeatPress(oldPress)
        try service.endPress(oldPress)
        #expect(poster.events.count == 6)
        try service.repeatPress(newPress)
        try service.endPress(newPress)
        #expect(
            Array(poster.events.suffix(3)) == [
                .key(.a, [], true), .keyRepeat(.a, []), .key(.a, [], false),
            ]
        )
        service.releaseAll()
        try service.endPress(newPress)
        #expect(poster.events.count == 8)
    }

    // MARK: - Held Key Down Failure
    @Test func failedKeyDownReleasesTransferredLatchAndCanBeRetried() throws {
        let poster = FakeKeyboardEventPoster()
        poster.failingKeyPostAttempts = [2]
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleLatch(.leftShift)
        #expect(throws: KeyboardServiceError.eventCreationFailed) {
            try service.beginPress(KeyStroke(.a, modifiers: [.shift]))
        }
        #expect(service.lastError == .eventCreationFailed)
        #expect(service.latchedModifiers.isEmpty)
        #expect(poster.events == [.key(.leftShift, [.shift], true), .key(.leftShift, [], false)])
        service.releaseAll()
        #expect(poster.keyPostAttempts == 3)

        try service.toggleLatch(.leftShift)
        let press = try service.beginPress(KeyStroke(.a, modifiers: [.shift]))
        #expect(service.lastError == nil)
        try service.repeatPress(press)
        try service.endPress(press)
        #expect(
            Array(poster.events.suffix(5)) == [
                .key(.leftShift, [.shift], true), .key(.a, [.shift], true),
                .keyRepeat(.a, [.shift]), .key(.a, [.shift], false), .key(.leftShift, [], false),
            ]
        )
    }

    // MARK: - Held Key Up Failure
    @Test(arguments: [false, true])
    func failedKeyUpRetainsPressAndModifiersForRetry(usingCleanup: Bool) throws {
        let poster = FakeKeyboardEventPoster()
        poster.failingKeyPostAttempts = [4]
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleLatch(.leftShift)
        let press = try service.beginPress(KeyStroke(.a, modifiers: [.shift]))
        try service.repeatPress(press)
        #expect(throws: KeyboardServiceError.eventCreationFailed) {
            try service.endPress(press)
        }
        #expect(service.lastError == .eventCreationFailed)
        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true), .key(.a, [.shift], true),
                .keyRepeat(.a, [.shift]),
            ]
        )
        if usingCleanup {
            service.releaseAll()
        }
        else {
            try service.endPress(press)
        }
        #expect(service.lastError == nil)
        #expect(
            Array(poster.events.suffix(2)) == [
                .key(.a, [.shift], false), .key(.leftShift, [], false),
            ]
        )
        try service.repeatPress(press)
        try service.endPress(press)
        service.releaseAll()
        #expect(poster.keyPostAttempts == 6)
        #expect(poster.events.count == 5)
    }

    // MARK: - Held Key Repeat Failure
    @Test func failedRepeatRetainsPressForRetryAndPairedRelease() throws {
        let poster = FakeKeyboardEventPoster()
        poster.failingKeyPostAttempts = [2]
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        let press = try service.beginPress(KeyStroke(.a))
        #expect(throws: KeyboardServiceError.eventCreationFailed) {
            try service.repeatPress(press)
        }
        #expect(service.lastError == .eventCreationFailed)
        #expect(poster.events == [.key(.a, [], true)])
        try service.repeatPress(press)
        try service.endPress(press)
        #expect(service.lastError == nil)
        #expect(poster.events == [.key(.a, [], true), .keyRepeat(.a, []), .key(.a, [], false)])
    }

    // MARK: - Release Edge Cases
    @Test func modifierReleaseFailureKeepsPressWithoutRepeatingTheReleasedKey() throws {
        let poster = FakeKeyboardEventPoster()
        poster.failingKeyPostAttempts = [4]
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleLatch(.leftShift)
        let press = try service.beginPress(KeyStroke(.a, modifiers: [.shift]))
        #expect(throws: KeyboardServiceError.eventCreationFailed) {
            try service.endPress(press)
        }
        try service.repeatPress(press)
        #expect(poster.keyPostAttempts == 4)
        try service.endPress(press)
        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true), .key(.a, [.shift], true),
                .key(.a, [.shift], false), .key(.leftShift, [], false),
            ]
        )
    }

    @Test func physicalOverlapDoesNotLoseOwnershipOfEarlierSyntheticModifier() throws {
        let hardware = FakeHardwareState()
        let physical = PhysicalKeyboardState(
            readHardware: { hardware.snapshot },
            canObserve: { true }
        )
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster,
            physicalKeyboard: physical
        )
        try service.toggleLatch(.leftShift)
        hardware.snapshot = PhysicalKeyboardSnapshot(
            pressedKeys: [.rightShift],
            modifiers: [.rightShift]
        )
        physical.refresh()
        try service.tap(KeyStroke(.a, modifiers: [.shift]))
        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true), .key(.a, [.shift], true),
                .key(.a, [.shift], false), .key(.leftShift, [.shift], false),
            ]
        )
    }

    @Test func heldKeyRepeatAndReleaseFollowPhysicalModifiers() throws {
        let hardware = FakeHardwareState()
        hardware.snapshot = PhysicalKeyboardSnapshot(
            pressedKeys: [.leftShift],
            modifiers: [.leftShift]
        )
        let physical = PhysicalKeyboardState(
            readHardware: { hardware.snapshot },
            canObserve: { true }
        )
        physical.refresh()
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster,
            physicalKeyboard: physical
        )
        let press = try service.beginPress(KeyStroke(.a, modifiers: [.shift]))
        hardware.snapshot = PhysicalKeyboardSnapshot()
        physical.refresh()
        try service.repeatPress(press)
        hardware.snapshot = PhysicalKeyboardSnapshot(
            pressedKeys: [.leftOption],
            modifiers: [.leftOption]
        )
        physical.refresh()
        try service.endPress(press)
        #expect(
            poster.events == [
                .key(.a, [.shift], true), .keyRepeat(.a, []), .key(.a, [.option], false),
            ]
        )
    }

    @Test func heldKeyUsesReResolvedFlagsWhenGiven() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        let press = try service.beginPress(KeyStroke(.a, modifiers: [.capsLock]))
        try service.repeatPress(press, modifiers: [])
        try service.endPress(press, modifiers: [])
        #expect(
            poster.events == [
                .key(.a, [.capsLock], true), .keyRepeat(.a, []), .key(.a, [], false),
            ]
        )
    }
}
