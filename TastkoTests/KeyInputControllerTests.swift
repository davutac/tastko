import CoreGraphics
import Defaults
import Foundation
import Testing

@testable import Tastko

// MARK: - KeyInputControllerTests
@Suite(.serialized)
@MainActor
struct KeyInputControllerTests {
    private let poster = FakeKeyboardEventPoster()
    private let soundPlayer = FakeSystemSoundPlayer(soundID: 7)
    private let keyboard: KeyboardService

    init() {
        keyboard = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(target: keyboardServiceTarget()),
            eventPoster: poster
        )
    }

    // MARK: - Taps
    @Test func oneShotModifierLatchesAndTheNextKeyConsumesIt() {
        let controller = makeController()
        controller.press(button(.modifier(.leftShift), behavior: .oneShot), with: .leftClick)
        #expect(keyboard.latchedModifiers == [.leftShift])

        let escape = button(.keyStroke(KeyStroke(.escape)))
        controller.press(escape, with: .leftClick)
        controller.release(escape)

        #expect(
            poster.events == [
                .key(.leftShift, [.shift], true),
                .key(.escape, [.shift], true), .key(.escape, [.shift], false),
                .key(.leftShift, [], false),
            ]
        )
        #expect(keyboard.latchedModifiers.isEmpty)
        #expect(soundPlayer.playedSoundIDs.count == 2)
    }

    @Test func pressAndReleaseModifierTapsWithoutLatching() {
        let controller = makeController()
        controller.press(button(.modifier(.leftOption)), with: .leftClick)
        #expect(
            poster.events == [.key(.leftOption, [.option], true), .key(.leftOption, [], false)]
        )
        #expect(keyboard.latchedModifiers.isEmpty)
    }

    @Test func functionModifierTogglesTheFnHold() {
        let controller = makeController()
        let fn = button(.modifier(.function), behavior: .oneShot)
        controller.press(fn, with: .leftClick)
        #expect(keyboard.heldModifiers == [.function])
        #expect(controller.isEngaged(fn))
        controller.press(fn, with: .leftClick)
        #expect(keyboard.heldModifiers.isEmpty)
    }

    @Test func accessibilityActivationTapsWithoutHoldingOrSound() {
        let controller = makeController()
        controller.activate(button(.keyStroke(KeyStroke(.delete))), with: .leftClick)
        #expect(poster.events == [.key(.delete, [], true), .key(.delete, [], false)])
        #expect(soundPlayer.playedSoundIDs.isEmpty)
    }

    @Test func functionToolbarToggleRunsTheWindowAction() {
        var toggles = 0
        let controller = makeController { toggles += 1 }
        controller.press(button(.toggleFunctionToolbar), with: .leftClick)
        #expect(toggles == 1)
        #expect(poster.events.isEmpty)
    }

    // MARK: - Holds
    @Test func heldKeyStaysDownUntilReleaseAndReleasesItsLatch() {
        let controller = makeController()
        controller.press(button(.modifier(.leftCommand), behavior: .oneShot), with: .leftClick)
        let delete = button(.keyStroke(KeyStroke(.delete)))
        controller.press(delete, with: .leftClick)
        #expect(poster.events.last == .key(.delete, [.command], true))

        controller.release(delete)
        #expect(
            Array(poster.events.suffix(2)) == [
                .key(.delete, [.command], false), .key(.leftCommand, [], false),
            ]
        )
        controller.release(delete)
        #expect(poster.events.count == 4)
    }

    @Test func heldKeyRepeatsWithSoundAfterTheDelay() async throws {
        let controller = makeController(timing: KeyRepeatTiming(delay: .zero, interval: .zero))
        let delete = button(.keyStroke(KeyStroke(.delete)))
        controller.press(delete, with: .leftClick)
        try await waitUntil { poster.events.count >= 3 }
        controller.release(delete)

        let repeats = poster.events.filter { $0 == .keyRepeat(.delete, []) }
        #expect(repeats.count >= 2)
        #expect(poster.events.first == .key(.delete, [], true))
        #expect(poster.events.last == .key(.delete, [], false))
        #expect(soundPlayer.playedSoundIDs.count >= repeats.count + 1)
    }

    @Test func cancellingInputStopsRepeatingAndReleasesTheKey() async throws {
        let controller = makeController(timing: KeyRepeatTiming(delay: .zero, interval: .zero))
        let delete = button(.keyStroke(KeyStroke(.delete)))
        controller.press(delete, with: .leftClick)
        try await waitUntil { poster.events.count >= 2 }
        keyboard.cancelPresses()
        #expect(poster.events.last == .key(.delete, [], false))
        let count = poster.events.count
        try await Task.sleep(for: .milliseconds(20))
        #expect(poster.events.count == count)
        controller.release(delete)
        #expect(poster.events.count == count)
    }

    @Test func heldTextKeyTypesImmediatelyAndRepeatsUntilRelease() async throws {
        let controller = makeController(timing: KeyRepeatTiming(delay: .zero, interval: .zero))
        let text = button(.text("é"))
        controller.press(text, with: .leftClick)
        #expect(poster.events == [.text("é", 1234, .textElement)])
        try await waitUntil { poster.events.count >= 3 }
        controller.release(text)
        let count = poster.events.count
        try await Task.sleep(for: .milliseconds(20))
        #expect(poster.events.count == count)
    }

    // MARK: - Function Toolbar
    @Test func functionToolbarKeyCarriesLatchedModifiers() {
        let controller = makeController()
        controller.press(button(.modifier(.leftCommand), behavior: .oneShot), with: .leftClick)
        controller.press(
            FunctionToolbarItem(id: 3, title: "F3", symbol: nil, action: .key(.f3))
        )
        #expect(
            poster.events == [
                .key(.leftCommand, [.command], true),
                .key(.f3, [.command], true), .key(.f3, [.command], false),
                .key(.leftCommand, [], false),
            ]
        )
    }

    // MARK: - Fixtures
    private func makeController(
        timing: KeyRepeatTiming = KeyRepeatTiming(delay: .seconds(60), interval: .seconds(60)),
        toggleFunctionToolbar: @escaping @MainActor () -> Void = {}
    ) -> KeyInputController {
        let suite = UserDefaults(suiteName: "KeyInputControllerTests-\(UUID().uuidString)")!
        return KeyInputController(
            keyboard: keyboard,
            languages: KeyboardLanguageService(),
            sounds: SoundService(
                soundPlayer: soundPlayer,
                preference: Defaults.Key("buttonSound", default: .keyClick, suite: suite)
            ),
            timing: timing,
            toggleFunctionToolbar: toggleFunctionToolbar
        )
    }

    private func button(
        _ action: KeyAction,
        behavior: KeyPressBehavior = .pressAndRelease
    ) -> PanelEditorButton {
        PanelEditorButton(
            id: UUID().uuidString,
            frame: CGRect(x: 0, y: 0, width: 40, height: 40),
            title: "Key",
            secondaryTitle: nil,
            fontSize: 12,
            backgroundColor: nil,
            foregroundColor: nil,
            shape: .rectangle,
            primaryAction: action,
            secondaryAction: .none,
            pressBehavior: behavior
        )
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting for key repeat")
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}
