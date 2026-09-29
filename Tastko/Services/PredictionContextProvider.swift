import Carbon

// MARK: - PredictionContextProviding
@MainActor
protocol PredictionContextProviding {
    func capture(language: String) -> PredictionContext?
    func startObserving(_ changed: @escaping @MainActor () -> Void)
    func stopObserving()
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
    private var lastLanguage = ""
    private let snapshot: @MainActor (String) -> PredictionContextSnapshot
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
        }
    ) {
        self.observesSystem = observesSystem
        self.inputSource = inputSource
        self.snapshot = snapshot
    }

    // MARK: - Context
    func capture(language: String) -> PredictionContext? {
        guard changed != nil else { return nil }
        if lastLanguage != language {
            clearBuffer()
            lastLanguage = language
        }
        switch snapshot(language) {
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
        guard case .unreadable(let target, let selection) = snapshot(lastLanguage) else {
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
            case .unreadable(let current, _) = snapshot(lastLanguage),
            current.hasSameFocus(as: preparedInput.target)
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
    }
}
