import Carbon

// MARK: - PredictionContextProviding
@MainActor
protocol PredictionContextProviding {
    func capture(language: String) -> PredictionContext?
    func startObserving(_ changed: @escaping @MainActor () -> Void)
    func stopObserving()
    /// Whether the focused element reports its own text and selection changes.
    var receivesChangeNotifications: Bool { get }
}

extension PredictionContextProviding {
    var receivesChangeNotifications: Bool { false }
}

// MARK: - AccessibilityPredictionContextProvider
@MainActor
final class AccessibilityPredictionContextProvider: PredictionContextProviding,
    KeyboardTypingObserving
{
    private var observation: PredictionContextObservation?
    private var changed: (@MainActor () -> Void)?
    private var buffer = PredictionTypingBuffer()
    private var translator = PredictionKeyTranslator()
    private var preparedInput: (target: FocusedKeyboardTarget, source: String?)?
    /// The target of the last capture when it could read the field's text.
    private var lastReadableTarget: FocusedKeyboardTarget?
    private var lastLanguage = ""
    private let snapshot: @MainActor (String) -> PredictionContextSnapshot
    private let focusCheck: (@MainActor (FocusedKeyboardTarget) -> Bool)?
    private let inputSource: @MainActor () -> String?
    private let observesSystem: Bool

    // MARK: - Initialization
    init(
        observesSystem: Bool = true,
        inputSource: @escaping @MainActor () -> String? = {
            PredictionKeyTranslator.inputSourceID()
        },
        snapshot: @escaping @MainActor (String) -> PredictionContextSnapshot = { language in
            guard !IsSecureEventInputEnabled(),
                let target = try? AccessibilityService.shared.focusedKeyboardTarget()
            else { return .ineligible }
            return AccessibilityService.shared.predictionSnapshot(for: target, language: language)
        },
        focusMatches: (@MainActor (FocusedKeyboardTarget) -> Bool)? = nil
    ) {
        self.observesSystem = observesSystem
        self.inputSource = inputSource
        self.snapshot = snapshot
        self.focusCheck = focusMatches
    }

    // MARK: - Focus Check
    /// Checks focus with two Accessibility requests instead of a full text snapshot.
    static func accessibilityFocusMatches(_ target: FocusedKeyboardTarget) -> Bool {
        !IsSecureEventInputEnabled() && AccessibilityService.shared.isFocused(on: target)
    }

    /// Whether focus is still on `target`. Without a cheaper check, compares against
    /// a full snapshot.
    private func focusMatches(_ target: FocusedKeyboardTarget) -> Bool {
        if let focusCheck { return focusCheck(target) }
        return snapshot(lastLanguage).target?.hasSameFocus(as: target) == true
    }

    var receivesChangeNotifications: Bool {
        observation?.observesElementChanges == true
    }

    // MARK: - Context
    func capture(language: String) -> PredictionContext? {
        guard changed != nil else { return nil }
        if lastLanguage != language {
            clearBuffer()
            lastLanguage = language
        }
        let snapshot = snapshot(language)
        lastReadableTarget = snapshot.readableTarget
        switch snapshot {
        case .readable(let context):
            observation?.observeApplication(context.target.processIdentifier)
            observation?.observeElement(context.target.focusedTextElement)
            clearBuffer()
            return context
        case .unreadable(let target, let selection):
            observation?.observeApplication(target.processIdentifier)
            observation?.observeElement(target.focusedTextElement ?? target.focusedElement)
            observeTypingTarget(target, selection: selection, source: inputSource())
            guard !translator.isComposing else { return nil }
            return buffer.context(language: language)
        case .ineligible:
            observation?.observeApplication()
            observation?.observeElement(nil)
            clearBuffer()
            return nil
        }
    }

    // MARK: - Posted Input
    func prepareForInput() {
        preparedInput = nil
        guard changed != nil else { return }
        // This runs before every key is posted. A readable field needs no typing
        // buffer, so confirm focus stayed on it rather than reading its text again.
        if let lastReadableTarget, focusMatches(lastReadableTarget) {
            clearBuffer()
            return
        }
        let snapshot = snapshot(lastLanguage)
        lastReadableTarget = snapshot.readableTarget
        guard case .unreadable(let target, let selection) = snapshot else {
            clearBuffer()
            return
        }
        let source = inputSource()
        observeTypingTarget(target, selection: selection, source: source)
        preparedInput = (target, source)
    }

    func didPostText(_ text: String) {
        guard preparedInput != nil else { return }
        translator.reset()
        record(.insert(text))
    }

    func didPostKey(_ stroke: KeyStroke) {
        guard preparedInput != nil else { return }
        record(translator.edit(for: stroke))
    }

    private func record(_ edit: PredictionTypingEdit) {
        guard changed != nil, let preparedInput,
            preparedInput.source == inputSource(),
            focusMatches(preparedInput.target)
        else {
            resetTypingSession()
            return
        }
        self.preparedInput = nil
        buffer.apply(edit)
        if edit == .reset { translator.reset() }
        changed?()
    }

    func resetTypingSession() {
        clearBuffer()
        lastReadableTarget = nil
        changed?()
    }

    private func clearBuffer() {
        buffer.reset()
        translator.reset()
        preparedInput = nil
    }

    private func observeTypingTarget(
        _ target: FocusedKeyboardTarget,
        selection: AccessibilityTextRange?,
        source: String?
    ) {
        let previousSession = buffer.session
        buffer.observe(target: target, selection: selection, inputSource: source)
        if buffer.session != previousSession { translator.reset() }
    }

    // MARK: - Observation Lifecycle
    func startObserving(_ changed: @escaping @MainActor () -> Void) {
        stopObserving()
        self.changed = changed
        guard observesSystem else { return }
        observation = PredictionContextObservation(
            changed: { [weak self] in self?.changed?() },
            reset: { [weak self] in self?.resetTypingSession() }
        )
        observation?.start()
    }

    func stopObserving() {
        changed = nil
        observation?.stop()
        observation = nil
        clearBuffer()
        lastReadableTarget = nil
    }
}

// MARK: - Snapshot Target
extension PredictionContextSnapshot {
    fileprivate var target: FocusedKeyboardTarget? {
        switch self {
        case .readable(let context): context.target
        case .unreadable(let target, _): target
        case .ineligible: nil
        }
    }

    fileprivate var readableTarget: FocusedKeyboardTarget? {
        guard case .readable(let context) = self else { return nil }
        return context.target
    }
}
