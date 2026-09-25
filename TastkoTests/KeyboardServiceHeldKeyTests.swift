import CoreGraphics
import Foundation
import Testing

@testable import Tastko

// MARK: - Held Keys
extension KeyboardServiceTests {
    // MARK: - Held Key Lifecycle
    @Test func mouseDownWaitsForReleaseAndRepeatsNeverPostPrematureKeyUp() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        let token = try service.beginKeyPress(KeyStroke(.delete), latchedModifiers: [])
        #expect(poster.events == [.key(.delete, [], true)])

        try service.repeatKeyPress(token)
        try service.repeatKeyPress(token)
        #expect(
            poster.events == [
                .key(.delete, [], true), .keyRepeat(.delete, []), .keyRepeat(.delete, []),
            ]
        )

        try service.endKeyPress(token)
        #expect(
            poster.events == [
                .key(.delete, [], true), .keyRepeat(.delete, []), .keyRepeat(.delete, []),
                .key(.delete, [], false),
            ]
        )
        try service.repeatKeyPress(token)
        try service.endKeyPress(token)
        #expect(poster.events.count == 4)
    }

    // MARK: - Held Key Sticky Modifiers
    @Test func transferredStickyModifiersStayDownThroughRepeatsAndReleaseAfterKeyUp() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleOneShotModifier(.leftCommand)
        try service.toggleOneShotModifier(.leftShift)
        let modifiers = service.consumeActiveOneShotModifiers()
        let token = try service.beginKeyPress(KeyStroke(.a), latchedModifiers: modifiers)
        try service.repeatKeyPress(token)
        try service.repeatKeyPress(token)
        #expect(service.activeOneShotModifiers.isEmpty)
        #expect(
            poster.events == [
                .key(.leftCommand, [.command], true),
                .key(.leftShift, [.command, .shift], true),
                .key(.a, [.command, .shift], true),
                .keyRepeat(.a, [.command, .shift]), .keyRepeat(.a, [.command, .shift]),
            ]
        )

        try service.endKeyPress(token)
        #expect(
            Array(poster.events.suffix(3)) == [
                .key(.a, [.command, .shift], false),
                .key(.leftShift, [.command], false), .key(.leftCommand, [], false),
            ]
        )
        service.releaseAllModifiers()
        #expect(poster.events.count == 8)
    }

    // MARK: - Held Key Shortcut Modifiers
    @Test func heldShortcutStrokePressesModifierKeysUntilRelease() throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )

        let token = try service.beginKeyPress(
            KeyStroke(.equal, modifiers: [.control, .command]),
            latchedModifiers: []
        )
        try service.endKeyPress(token)

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
    func cleanupReleasesKeyBeforeModifiersAndStaleTokenCannotAffectNewPress(
        lockTransition: Bool
    ) throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster,
            canPostEvents: { true }
        )
        try service.toggleOneShotModifier(.leftShift)
        let oldToken = try service.beginKeyPress(
            KeyStroke(.a),
            latchedModifiers: service.consumeActiveOneShotModifiers()
        )
        try service.repeatKeyPress(oldToken)
        let session = service.inputSession
        if lockTransition {
            service.setScreenLocked(true, allowsInput: true)
        }
        else {
            service.releaseAllModifiers()
        }
        #expect(service.inputSession != session)
        #expect(service.activeOneShotModifiers.isEmpty)
        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true), .key(.a, [.shift], true),
                .keyRepeat(.a, [.shift]), .key(.a, [.shift], false),
                .key(.leftShift, [], false),
            ]
        )
        let newToken = try service.beginKeyPress(KeyStroke(.a), latchedModifiers: [])
        #expect(newToken != oldToken)
        try service.repeatKeyPress(oldToken)
        try service.endKeyPress(oldToken)
        #expect(poster.events.count == 6)
        try service.repeatKeyPress(newToken)
        try service.endKeyPress(newToken)
        #expect(
            Array(poster.events.suffix(3)) == [
                .key(.a, [], true), .keyRepeat(.a, []), .key(.a, [], false),
            ]
        )
        service.releaseAllModifiers()
        try service.endKeyPress(newToken)
        #expect(poster.events.count == 8)
    }

    // MARK: - Held Key Down Failure
    @Test func failedKeyDownReleasesTransferredModifiersAndCanBeRetried() throws {
        let poster = FakeKeyboardEventPoster()
        poster.failingKeyPostAttempts = [2]
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleOneShotModifier(.leftShift)
        let modifiers = service.consumeActiveOneShotModifiers()
        #expect(throws: KeyboardServiceError.eventCreationFailed) {
            try service.beginKeyPress(KeyStroke(.a), latchedModifiers: modifiers)
        }
        #expect(service.lastError == .eventCreationFailed)
        #expect(poster.events == [.key(.leftShift, [.shift], true), .key(.leftShift, [], false)])
        service.releaseAllModifiers()
        #expect(poster.keyPostAttempts == 3)

        let token = try service.beginKeyPress(KeyStroke(.a), latchedModifiers: modifiers)
        #expect(service.lastError == nil)
        try service.repeatKeyPress(token)
        try service.endKeyPress(token)
        #expect(
            Array(poster.events.suffix(5)) == [
                .key(.leftShift, [.shift], true), .key(.a, [.shift], true),
                .keyRepeat(.a, [.shift]), .key(.a, [.shift], false), .key(.leftShift, [], false),
            ]
        )
    }

    // MARK: - Held Key Up Failure
    @Test(arguments: [false, true])
    func failedKeyUpRetainsTokenAndModifiersForRetry(usingCleanup: Bool) throws {
        let poster = FakeKeyboardEventPoster()
        poster.failingKeyPostAttempts = [4]
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleOneShotModifier(.leftShift)
        let token = try service.beginKeyPress(
            KeyStroke(.a),
            latchedModifiers: service.consumeActiveOneShotModifiers()
        )
        try service.repeatKeyPress(token)
        #expect(throws: KeyboardServiceError.eventCreationFailed) {
            try service.endKeyPress(token)
        }
        #expect(service.lastError == .eventCreationFailed)
        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true), .key(.a, [.shift], true),
                .keyRepeat(.a, [.shift]),
            ]
        )
        if usingCleanup {
            service.releaseAllModifiers()
        }
        else {
            try service.endKeyPress(token)
        }
        #expect(service.lastError == nil)
        #expect(
            Array(poster.events.suffix(2)) == [
                .key(.a, [.shift], false), .key(.leftShift, [], false),
            ]
        )
        try service.repeatKeyPress(token)
        try service.endKeyPress(token)
        service.releaseAllModifiers()
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
        let token = try service.beginKeyPress(KeyStroke(.a), latchedModifiers: [])
        #expect(throws: KeyboardServiceError.eventCreationFailed) {
            try service.repeatKeyPress(token)
        }
        #expect(service.lastError == .eventCreationFailed)
        #expect(poster.events == [.key(.a, [], true)])
        try service.repeatKeyPress(token)
        try service.endKeyPress(token)
        #expect(service.lastError == nil)
        #expect(poster.events == [.key(.a, [], true), .keyRepeat(.a, []), .key(.a, [], false)])
    }

    // MARK: - Release Edge Cases
    @Test func modifierReleaseFailureKeepsTokenWithoutRepeatingTheReleasedKey() throws {
        let poster = FakeKeyboardEventPoster()
        poster.failingKeyPostAttempts = [4]
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        try service.toggleOneShotModifier(.leftShift)
        let token = try service.beginKeyPress(
            KeyStroke(.a),
            latchedModifiers: service.consumeActiveOneShotModifiers()
        )
        #expect(throws: KeyboardServiceError.eventCreationFailed) {
            try service.endKeyPress(token)
        }
        try service.repeatKeyPress(token)
        #expect(poster.keyPostAttempts == 4)
        try service.endKeyPress(token)
        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true), .key(.a, [.shift], true),
                .key(.a, [.shift], false), .key(.leftShift, [], false),
            ]
        )
    }

    @Test func physicalOverlapDoesNotLoseOwnershipOfEarlierSyntheticModifier() async throws {
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
        try service.toggleOneShotModifier(.leftShift)
        hardware.snapshot = PhysicalKeyboardSnapshot(
            pressedKeys: [.rightShift],
            modifiers: [.rightShift]
        )
        physical.refresh()
        try await service.perform(.keyStroke(KeyStroke(.a)))
        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true), .key(.a, [.shift], true),
                .key(.a, [.shift], false), .key(.leftShift, [.shift], false),
            ]
        )
    }

    @Test func heldKeyRepeatAndReleaseUseCurrentPhysicalModifiers() throws {
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
        let token = try service.beginKeyPress(
            KeyStroke(.a, modifiers: [.shift]),
            latchedModifiers: []
        )
        hardware.snapshot = PhysicalKeyboardSnapshot()
        physical.refresh()
        try service.repeatKeyPress(token)
        hardware.snapshot = PhysicalKeyboardSnapshot(
            pressedKeys: [.leftOption],
            modifiers: [.leftOption]
        )
        physical.refresh()
        try service.endKeyPress(token)
        #expect(
            poster.events == [
                .key(.a, [.shift], true), .keyRepeat(.a, []), .key(.a, [.option], false),
            ]
        )
    }
}
