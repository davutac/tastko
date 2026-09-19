import AppKit
import IOKit
import Testing

@testable import Tastko

// MARK: - PhysicalKeyboardStateTests
@MainActor
struct PhysicalKeyboardStateTests {
    // MARK: - Presses
    @Test func simultaneousKeysRepeatAndReleaseIndependently() throws {
        let state = PhysicalKeyboardState(canObserve: { true })
        state.receive(try event(.a, down: true))
        state.receive(try event(.b, down: true))
        state.receive(try event(.a, down: true, repeating: true))
        #expect(state.snapshot.pressedKeys == [.a, .b])
        state.receive(try event(.a, down: false))
        #expect(state.snapshot.pressedKeys == [.b])
        state.receive(try event(.b, down: false))
        #expect(state.snapshot.pressedKeys.isEmpty)
    }

    @Test func ignoresOurSyntheticEvents() throws {
        let state = PhysicalKeyboardState(canObserve: { true })
        let cgEvent = try #require(
            CGEvent(keyboardEventSource: nil, virtualKey: Key.a.rawValue, keyDown: true)
        )
        cgEvent.setIntegerValueField(
            .eventSourceUserData,
            value: CGKeyboardEventPoster.predictionEventTag
        )
        state.receive(try #require(NSEvent(cgEvent: cgEvent)))
        #expect(state.snapshot.pressedKeys.isEmpty)
    }

    // MARK: - Synthetic Input Reconciliation
    @Test func delayedSyntheticReleaseDoesNotClearANewerPostedPress() throws {
        var hardware = PhysicalKeyboardSnapshot()
        let state = PhysicalKeyboardState(readHardware: { hardware }, canObserve: { true })
        state.recordPostedKey(.a, isDown: true)
        state.recordPostedKey(.a, isDown: false)
        state.recordPostedKey(.a, isDown: true)

        // The previous click is observed before the system processes the next down.
        state.receive(try syntheticEvent(.a, down: false))
        state.refresh()
        hardware.pressedKeys = [.a]
        state.refresh()
        #expect(state.snapshot.pressedKeys.isEmpty)
    }

    @Test(arguments: ModifierKey.allCases)
    func postedModifiersStaySeparateAcrossRefreshAndReset(modifier: ModifierKey) {
        var hardware = PhysicalKeyboardSnapshot()
        let state = PhysicalKeyboardState(readHardware: { hardware }, canObserve: { true })
        // Delivery registers the key before posting, including flagsChanged events.
        state.recordPostedKey(modifier.key, isDown: true)
        hardware.pressedKeys = [modifier.key, .a]
        hardware.modifiers = [modifier]
        state.refresh()
        #expect(state.snapshot.pressedKeys == [.a])
        #expect(state.snapshot.modifiers.isEmpty)

        state.reset()
        state.refresh()
        #expect(state.snapshot.pressedKeys == [.a])
        #expect(state.snapshot.modifiers.isEmpty)
        state.recordPostedKey(modifier.key, isDown: false)
        state.refresh()
        #expect(state.snapshot.modifiers.isEmpty)

        hardware.pressedKeys = [.a]
        hardware.modifiers = []
        state.refresh()
        // Once delivery settles, hardware reconciliation works normally again.
        hardware.pressedKeys.insert(modifier.key)
        hardware.modifiers = [modifier]
        state.refresh()
        #expect(state.snapshot.modifiers == [modifier])
    }

    @Test func repeatedVirtualClicksNeverBecomePhysicalPressesDuringPolling() throws {
        var hardware = PhysicalKeyboardSnapshot()
        let state = PhysicalKeyboardState(readHardware: { hardware }, canObserve: { true })

        for _ in 0..<4 {
            let down = try syntheticEvent(.a, down: true)
            let up = try syntheticEvent(.a, down: false)
            state.receive(down)
            hardware.pressedKeys = [.a]
            state.refresh()
            #expect(!state.snapshot.isPressed(.keyStroke(KeyStroke(.a))))

            state.receive(up)
            state.refresh()
            #expect(!state.snapshot.isPressed(.keyStroke(KeyStroke(.a))))
            hardware.pressedKeys = []
            state.refresh()
        }
    }

    @Test(arguments: [false, true])
    func physicalPressSurvivesOverlappingVirtualClicks(physicalPressFirst: Bool) throws {
        var hardware = PhysicalKeyboardSnapshot()
        let state = PhysicalKeyboardState(readHardware: { hardware }, canObserve: { true })
        if physicalPressFirst {
            hardware.pressedKeys = [.a]
            state.receive(try event(.a, down: true))
        }
        state.receive(try syntheticEvent(.a, down: true))
        if !physicalPressFirst {
            hardware.pressedKeys = [.a]
            state.receive(try event(.a, down: true))
        }
        state.refresh()
        #expect(state.snapshot.pressedKeys == [.a])

        state.receive(try syntheticEvent(.a, down: false))
        state.refresh()
        #expect(state.snapshot.pressedKeys == [.a])
        state.receive(try event(.a, down: false))
        state.refresh()
        #expect(state.snapshot.pressedKeys.isEmpty)
    }

    @Test func matchesPlainKeysAndCompleteShortcutChords() {
        let snapshot = PhysicalKeyboardSnapshot(pressedKeys: [.c], modifiers: [.rightCommand])
        #expect(snapshot.isPressed(.keyStroke(KeyStroke(.c))))
        #expect(snapshot.isPressed(.keyStroke(KeyStroke(.c, modifiers: [.command]))))
        #expect(!snapshot.isPressed(.keyStroke(KeyStroke(.c, modifiers: [.command, .shift]))))
        #expect(!snapshot.isPressed(.text("c")))
        #expect(snapshot.isPressed(.modifier(.rightCommand)))
        #expect(!snapshot.isPressed(.modifier(.leftCommand)))
        let extraModifier = PhysicalKeyboardSnapshot(
            pressedKeys: [.c],
            modifiers: [.rightCommand, .leftShift]
        )
        #expect(!extraModifier.isPressed(.keyStroke(KeyStroke(.c, modifiers: [.command]))))
    }

    // MARK: - Modifier Events
    @Test func flagsChangedTracksBothSidesAndCapsLockWithoutClearingOtherKeys() throws {
        var hardware = PhysicalKeyboardSnapshot(
            pressedKeys: [.leftShift, .rightShift, .function],
            modifiers: [.leftShift, .rightShift, .function],
            isCapsLockEnabled: true
        )
        let state = PhysicalKeyboardState(readHardware: { hardware }, canObserve: { true })
        state.receive(try event(.a, down: true))
        let changed = try #require(
            NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: [.shift, .function, .capsLock],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: Key.rightShift.rawValue
            )
        )
        state.receive(changed)
        #expect(state.snapshot.modifiers == [.leftShift, .rightShift, .function])
        #expect(state.snapshot.isCapsLockEnabled)
        #expect(state.snapshot.pressedKeys.contains(.a))
        hardware.modifiers.remove(.rightShift)
        hardware.pressedKeys.remove(.rightShift)
        state.receive(changed)
        #expect(state.snapshot.modifiers == [.leftShift, .function])
    }

    // MARK: - Fn Hardware State
    @Test(arguments: [false, true], [false, true])
    func fnFlagIsAuthoritativeEvenWhenKeycodeStateDisagrees(keyIsDown: Bool, flagIsDown: Bool) {
        let snapshot = PhysicalKeyboardState.hardwareSnapshot(
            pressedKeys: keyIsDown ? [.function, .a] : [.a],
            flags: flagIsDown ? .maskSecondaryFn : []
        )
        #expect(snapshot.modifiers.contains(.function) == flagIsDown)
        #expect(snapshot.pressedKeys.contains(.function) == flagIsDown)
        #expect(snapshot.pressedKeys.contains(.a))
    }

    // MARK: - Caps Lock Hardware State
    @Test(arguments: [false, true], [false, true])
    func systemLockOverridesHIDFlag(systemLock: Bool, hidLock: Bool) throws {
        let state = PhysicalKeyboardState(
            readHardware: {
                PhysicalKeyboardState.hardwareSnapshot(
                    pressedKeys: [.a, .rightShift],
                    flags: hidLock ? [.maskAlphaShift, .maskSecondaryFn] : [.maskSecondaryFn],
                    capsLockEnabled: systemLock
                )
            },
            canObserve: { true }
        )
        state.refresh()
        #expect(state.snapshot.isCapsLockEnabled == systemLock)
        #expect(state.snapshot.modifiers == [.rightShift, .function])
        #expect(state.snapshot.pressedKeys == [.a, .rightShift, .function])

        let changed = try #require(
            NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: Key.capsLock.rawValue
            )
        )
        state.receive(changed)
        #expect(state.snapshot.isCapsLockEnabled == systemLock)
    }

    // MARK: - Reconciliation
    @Test func refreshesBothModifierSidesAndRecoversMissedReleases() throws {
        var hardware = PhysicalKeyboardSnapshot(
            pressedKeys: [.leftOption, .rightOption],
            modifiers: [.leftOption, .rightOption],
            isCapsLockEnabled: true
        )
        let state = PhysicalKeyboardState(readHardware: { hardware }, canObserve: { true })
        state.refresh()
        #expect(state.snapshot == hardware)
        hardware.pressedKeys.remove(.leftOption)
        hardware.modifiers.remove(.leftOption)
        state.refresh()
        #expect(state.snapshot.modifiers == [.rightOption])
        state.receive(try event(.a, down: true))
        #expect(state.snapshot.pressedKeys.contains(.a))
        state.refresh()
        #expect(!state.snapshot.pressedKeys.contains(.a))
        state.stop()
        #expect(state.snapshot == PhysicalKeyboardSnapshot())
    }

    @Test func permissionLossClearsState() throws {
        var permitted = true
        let state = PhysicalKeyboardState(canObserve: { permitted })
        state.receive(try event(.a, down: true))
        permitted = false
        state.refresh()
        #expect(state.snapshot == PhysicalKeyboardSnapshot())
        state.receive(try event(.b, down: true))
        #expect(state.snapshot.pressedKeys.isEmpty)
    }

    // MARK: - Toolbar
    @Test func mediaKeysAndFunctionKeysHighlightTheToolbar() throws {
        let state = PhysicalKeyboardState(canObserve: { true })
        state.receive(try MacOSSystemControlPerformer.event(for: .playPause, keyDown: true))
        let item = try #require(
            FunctionToolbarItem.items(functionIsActive: false).first {
                $0.action == .system(.playPause)
            }
        )
        #expect(item.isPressed(in: state.snapshot))
        state.receive(try MacOSSystemControlPerformer.event(for: .playPause, keyDown: false))
        #expect(!item.isPressed(in: state.snapshot))
        #expect(PhysicalKeyboardState.control(for: Int(NX_KEYTYPE_BRIGHTNESS_UP)) == .brightnessUp)
        let f1 = try #require(
            FunctionToolbarItem.items(functionIsActive: true).first { $0.action == .key(.f1) }
        )
        #expect(f1.isPressed(in: PhysicalKeyboardSnapshot(pressedKeys: [.f1])))
    }

    // MARK: - Fixtures
    private func syntheticEvent(_ key: Key, down: Bool) throws -> NSEvent {
        try #require(
            NSEvent(cgEvent: CGKeyboardEventPoster().keyEvent(key, modifiers: [], keyDown: down))
        )
    }

    private func event(_ key: Key, down: Bool, repeating: Bool = false) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: down ? .keyDown : .keyUp,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: repeating,
                keyCode: key.rawValue
            )
        )
    }
}
