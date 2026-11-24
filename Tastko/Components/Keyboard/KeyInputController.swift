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
///
/// With swipe typing, a letter press waits for its release: a tap types its letter then, and
/// a press the pointer drags through a word's letters types the word instead. Letters don't
/// repeat while held then.
@MainActor
final class KeyInputController {
    static let shared = KeyInputController(
        swipe: .shared,
        swipeContext: { TextPredictionService.shared.swipeContext() },
        insertSwipedWord: {
            TextPredictionService.shared.insertSwipedWord($0, alternatives: $1, context: $2)
        }
    )

    private let keyboard: KeyboardService
    private let languages: KeyboardLanguageService
    private let sounds: SoundService
    private let toggleFunctionToolbar: @MainActor () -> Void
    private let timing: KeyRepeatTiming
    private let swipe: SwipeTypingController?
    private let swipeContext: () -> PredictionContext?
    private let insertSwipedWord: (String, [String], PredictionContext) -> Bool
    private var holds: [PanelEditorButton.ID: Hold] = [:]
    /// Where each press went down, reported just before the press itself.
    private var pointerOrigins: [PanelEditorButton.ID: (point: CGPoint, time: TimeInterval)] = [:]
    /// Letter presses waiting for their release, which may turn out to be swipes.
    private var deferredTaps: [PanelEditorButton.ID: DeferredTap] = [:]
    /// A swiped word went in without the field's text to space it by: the next one does,
    /// unless another key came between.
    private var swipedWordNeedsSpace = false

    // MARK: - Hold
    private struct Hold {
        let button: PanelEditorButton
        let trigger: KeyActionTrigger
        /// Latched modifiers when the press began; the press consumed them.
        let latchedModifiers: Set<ModifierKey>
        var press: KeyPress?
        var repeatTask: Task<Void, Never>?
    }

    // MARK: - DeferredTap
    private struct DeferredTap {
        let button: PanelEditorButton
        let trigger: KeyActionTrigger
        let action: KeyAction
        let latchedModifiers: Set<ModifierKey>
    }

    // MARK: - Initialization
    init(
        keyboard: KeyboardService? = nil,
        languages: KeyboardLanguageService? = nil,
        sounds: SoundService? = nil,
        timing: KeyRepeatTiming = KeyRepeatTiming(),
        swipe: SwipeTypingController? = nil,
        swipeContext: @escaping () -> PredictionContext? = { nil },
        insertSwipedWord: @escaping (String, [String], PredictionContext) -> Bool = { _, _, _ in
            false
        },
        toggleFunctionToolbar: (@MainActor () -> Void)? = nil
    ) {
        self.keyboard = keyboard ?? .shared
        self.languages = languages ?? .shared
        self.sounds = sounds ?? .shared
        self.timing = timing
        self.swipe = swipe
        self.swipeContext = swipeContext
        self.insertSwipedWord = insertSwipedWord
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
    /// Starts a pointer press. Repeatable keys stay down until `release(_:)`; a letter that
    /// may become a swipe types on `release(_:)` instead.
    func press(_ button: PanelEditorButton, with trigger: KeyActionTrigger) {
        endHold(button)
        deferredTaps[button.id] = nil
        sounds.play(.keyPress)
        let latchedModifiers = keyboard.latchedModifiers
        let action = resolve(button).action(for: trigger)
        let origin = pointerOrigins.removeValue(forKey: button.id)
        if let swipe, let origin,
            swipe.begin(buttonID: button.id, action: action, at: origin.point, time: origin.time)
        {
            deferredTaps[button.id] = DeferredTap(
                button: button,
                trigger: trigger,
                action: action,
                latchedModifiers: latchedModifiers
            )
            return
        }
        swipedWordNeedsSpace = false
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

    /// Ends a pointer press inside its key: a held key is released, and a letter waiting for
    /// its release types.
    func release(_ button: PanelEditorButton) {
        if let tap = deferredTaps.removeValue(forKey: button.id) {
            swipe?.cancel()
            type(tap)
            return
        }
        endHold(button)
    }

    /// Ends a pointer press without typing: dragged off its key, or interrupted.
    func cancel(_ button: PanelEditorButton) {
        pointerOrigins[button.id] = nil
        if deferredTaps.removeValue(forKey: button.id) != nil {
            swipe?.cancel()
        }
        endHold(button)
    }

    // MARK: - Pointer Positions
    /// Where a press goes down (panel coordinates) and when, reported before `press`.
    func pointerDown(_ button: PanelEditorButton, at point: CGPoint, time: TimeInterval) {
        pointerOrigins[button.id] = (point, time)
    }

    /// The pointer moved during `button`'s press. A letter press waiting for its release
    /// follows the pointer past its key, and becomes a swipe once it travels a key's pitch.
    func pointerMoved(
        _ button: PanelEditorButton,
        to point: CGPoint,
        time: TimeInterval
    ) -> KeyPointerDisposition {
        guard deferredTaps[button.id] != nil, let swipe else { return .standard }
        return swipe.move(buttonID: button.id, to: point, time: time) ? .swiping : .tracking
    }

    /// A letter press that followed the pointer was released at `point`: a swipe types its
    /// word, and a press that never travelled a key's pitch types its letter wherever it was
    /// released, as the letter typed on press before swipe typing.
    func pointerUp(
        _ button: PanelEditorButton,
        at point: CGPoint,
        time: TimeInterval,
        inside: Bool
    ) {
        guard let tap = deferredTaps.removeValue(forKey: button.id), let swipe else {
            if inside {
                release(button)
            }
            else {
                cancel(button)
            }
            return
        }
        let context = swipeContext()
        let previous = context.flatMap { SwipeVocabulary.previousWord(before: $0.input.context) }
        switch swipe.finish(buttonID: button.id, at: point, time: time, previous: previous) {
        case .notSwiped, .tap:
            type(tap)
        case .words(let words):
            typeSwipedWord(words.map { cased($0, for: tap) }, context: context)
            if tap.latchedModifiers.contains(where: { $0.modifiers.contains(.shift) }) {
                keyboard.releaseLatchedModifiers()
            }
        case .nothing:
            break
        }
    }

    // MARK: - Deferred Letters
    private func type(_ tap: DeferredTap) {
        swipedWordNeedsSpace = false
        perform(tap.action, behavior: tap.button.pressBehavior)
    }

    /// Inserts a swiped word, spaced by the field's text when it can be read; else after a
    /// space when the last thing typed was a swiped word.
    private func typeSwipedWord(_ words: [String], context: PredictionContext?) {
        guard let word = words.first else { return }
        if let context, insertSwipedWord(word, Array(words.dropFirst()), context) {
            swipedWordNeedsSpace = false
            return
        }
        let text = (swipedWordNeedsSpace ? " " : "") + word
        swipedWordNeedsSpace = (try? keyboard.type(text)) != nil
    }

    /// A swiped word in the case the press asked for. Posted text ignores Caps Lock, so it is
    /// applied here: Caps Lock types the word in capitals, or in lowercase with a right-click;
    /// Shift or a right-click gives it a capital.
    private func cased(_ word: String, for tap: DeferredTap) -> String {
        if keyboard.isCapsLockEnabled {
            return tap.trigger == .rightClick ? word.lowercased() : word.uppercased()
        }
        let shifted =
            tap.trigger == .rightClick
            || tap.latchedModifiers.union(keyboard.heldModifiers)
                .contains { $0.modifiers.contains(.shift) }
        return shifted ? word.prefix(1).uppercased() + word.dropFirst() : word
    }

    // MARK: - Holds
    /// Releases a held key, if the button holds one.
    private func endHold(_ button: PanelEditorButton) {
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
