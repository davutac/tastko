import Foundation

// MARK: - KeyRepeatTiming
nonisolated struct KeyRepeatTiming: Sendable {
    var delay: Duration = .milliseconds(350)
    var interval: Duration = .milliseconds(60)
}

// MARK: - KeyInputController
/// Turns on-screen key presses into keyboard output.
///
/// Views report pointer input; the controller resolves the key, decides between a
/// tap and a held press, repeats held keys, and plays key sounds. Keyboard output
/// itself goes through `KeyboardService`.
@MainActor
final class KeyInputController {
    static let shared = KeyInputController()

    private let keyboard: KeyboardService
    private let languages: KeyboardLanguageService
    private let sounds: SoundService
    private let toggleFunctionToolbar: @MainActor () -> Void
    private let timing: KeyRepeatTiming
    private var holds: [PanelEditorButton.ID: Hold] = [:]

    // MARK: - Hold
    private struct Hold {
        let button: PanelEditorButton
        let trigger: KeyActionTrigger
        /// Latched modifiers when the press began; the press consumed them.
        let latchedModifiers: Set<ModifierKey>
        var press: KeyPress?
        var repeatTask: Task<Void, Never>?
    }

    // MARK: - Initialization
    init(
        keyboard: KeyboardService? = nil,
        languages: KeyboardLanguageService? = nil,
        sounds: SoundService? = nil,
        timing: KeyRepeatTiming = KeyRepeatTiming(),
        toggleFunctionToolbar: (@MainActor () -> Void)? = nil
    ) {
        self.keyboard = keyboard ?? .shared
        self.languages = languages ?? .shared
        self.sounds = sounds ?? .shared
        self.timing = timing
        self.toggleFunctionToolbar =
            toggleFunctionToolbar ?? { FloatingWindowController.shared.toggleFunctionToolbar() }
    }

    // MARK: - Resolution
    /// Resolves a button against the current keyboard state. Views read this in
    /// `body`, so it tracks every observable input it depends on.
    func resolve(
        _ button: PanelEditorButton,
        latchedModifiers: Set<ModifierKey>? = nil
    ) -> ResolvedKey {
        KeyResolver.resolve(
            button,
            in: KeyResolutionContext(
                language: KeyboardLanguageContext(language: languages.selectedLanguage),
                labels: languages.keyLabels,
                latchedModifiers: latchedModifiers ?? keyboard.latchedModifiers,
                heldModifiers: keyboard.heldModifiers,
                isCapsLockEnabled: keyboard.isCapsLockEnabled
            )
        )
    }

    /// Whether the button shows as engaged: a latched or held modifier, or Caps Lock.
    func isEngaged(_ button: PanelEditorButton) -> Bool {
        switch button.primaryAction {
        case .keyStroke(let stroke) where stroke.key == .capsLock:
            keyboard.isCapsLockEnabled
        case .modifier(let modifier):
            keyboard.effectiveModifiers.contains(modifier)
        default:
            false
        }
    }

    // MARK: - Panel Keys
    /// Starts a pointer press. Repeatable keys stay down until `release(_:)`.
    func press(_ button: PanelEditorButton, with trigger: KeyActionTrigger) {
        release(button)
        sounds.play(.keyPress)
        let latchedModifiers = keyboard.latchedModifiers
        let action = resolve(button).action(for: trigger)
        guard action.isRepeatable else {
            perform(action, behavior: button.pressBehavior)
            return
        }
        var hold = Hold(button: button, trigger: trigger, latchedModifiers: latchedModifiers)
        switch action {
        case .keyStroke(let stroke):
            guard let press = try? keyboard.beginPress(stroke) else { return }
            hold.press = press
            let pressedHold = hold
            hold.repeatTask = repeatTask { [weak self] in
                guard let self else { return }
                try keyboard.repeatPress(press, modifiers: currentModifiers(of: pressedHold))
            }
        case .text(let text):
            // Text keys insert Unicode text instead of holding a physical key code.
            _ = try? keyboard.type(text)
            hold.repeatTask = repeatTask { [weak self] in _ = try? self?.keyboard.type(text) }
        default:
            return
        }
        holds[button.id] = hold
    }

    /// Ends a pointer press, releasing a held key.
    func release(_ button: PanelEditorButton) {
        guard var hold = holds[button.id] else { return }
        hold.repeatTask?.cancel()
        hold.repeatTask = nil
        if let press = hold.press {
            do { try keyboard.endPress(press, modifiers: currentModifiers(of: hold)) }
            catch {
                // Keep the press so a later release can retry the key up.
                holds[button.id] = hold
                return
            }
        }
        holds[button.id] = nil
    }

    /// Performs a key once without holding it, as an accessibility action does.
    func activate(_ button: PanelEditorButton, with trigger: KeyActionTrigger) {
        perform(resolve(button).action(for: trigger), behavior: button.pressBehavior)
    }

    // MARK: - Function Toolbar
    func press(_ item: FunctionToolbarItem) {
        sounds.play(.keyPress)
        switch item.action {
        case .key(let key):
            _ = try? keyboard.tap(KeyStroke(key, modifiers: keyboard.modifierFlags))
        case .system(let control):
            let inputSession = keyboard.inputSession
            Task {
                guard keyboard.inputSession == inputSession else { return }
                _ = try? await keyboard.perform(control)
            }
        }
    }

    // MARK: - Actions
    private func perform(_ action: KeyAction, behavior: KeyPressBehavior) {
        switch action {
        case .none:
            break
        case .text(let text):
            _ = try? keyboard.type(text)
        case .keyStroke(let stroke):
            _ = try? keyboard.tap(stroke)
        case .modifier(let modifier) where behavior == .oneShot:
            _ = try? keyboard.toggleLatch(modifier)
        case .modifier(let modifier):
            _ = try? keyboard.tapModifier(modifier)
        case .cycleKeyboardLanguage:
            languages.selectNextLanguage()
        case .toggleFunctionToolbar:
            toggleFunctionToolbar()
        }
    }

    // MARK: - Key Repeat
    /// Repeats a step after the initial delay until cancelled, a step fails, or the
    /// input session changes.
    private func repeatTask(_ step: @escaping @MainActor () throws -> Void) -> Task<Void, Never> {
        let inputSession = keyboard.inputSession
        return Task { [weak self, timing] in
            try? await Task.sleep(for: timing.delay)
            while !Task.isCancelled, let self, keyboard.inputSession == inputSession {
                sounds.play(.keyPress)
                do { try step() }
                catch { return }
                try? await Task.sleep(for: timing.interval)
            }
        }
    }

    /// Flags for a held key under the current physical modifiers and Caps Lock.
    private func currentModifiers(of hold: Hold) -> KeyModifiers? {
        guard
            case .keyStroke(let stroke) = resolve(
                hold.button,
                latchedModifiers: hold.latchedModifiers
            ).action(for: hold.trigger)
        else { return nil }
        return stroke.modifiers
    }
}
