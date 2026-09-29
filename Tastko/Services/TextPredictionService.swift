import AppKit
import Defaults
import Observation

// MARK: - TextPredictionService
@Observable
@MainActor
final class TextPredictionService {
    /// Native words that keep their positions ahead of contextual AI words.
    static let leadingNativeSuggestions = 3

    static let shared: TextPredictionService = {
        let keyboard = KeyboardService.shared
        let contextProvider = AccessibilityPredictionContextProvider()
        keyboard.typingObserver = contextProvider
        let service = TextPredictionService(
            contextProvider: contextProvider,
            nativeProvider: NativeWordPredictionProvider(),
            modelProvider: FoundationWordPredictionProvider(),
            language: {
                KeyboardLanguageService.shared.selectedLanguage?.languageCodes.first
                    ?? Locale.current.identifier
            },
            enabled: { Defaults[.textPredictionEnabled] },
            shortcutsActive: {
                let shortcuts: CGEventFlags = [
                    .maskCommand, .maskAlternate, .maskControl, .maskSecondaryFn,
                ]
                let physical = CGEventSource.flagsState(.combinedSessionState)
                return !physical.intersection(shortcuts).isEmpty
                    || keyboard.latchedModifiers.contains {
                        !$0.modifiers.intersection([.command, .option, .control, .function]).isEmpty
                    }
            },
            insert: { insertion, target in
                try keyboard.insertPrediction(
                    insertion.text,
                    deletingBackward: insertion.deleteBackwardCount,
                    into: target
                )
            }
        )
        keyboard.inputDidChange = { [weak service] in service?.keyboardDidChange() }
        return service
    }()

    @ObservationIgnored private var needsRefresh = true
    private(set) var completionContext: PredictionContext?
    private(set) var suggestions: [String] = []
    private(set) var typedPrefix = ""
    private(set) var hasTextContext = false
    private(set) var isRunning = false

    @ObservationIgnored private let contextProvider: any PredictionContextProviding
    @ObservationIgnored private let nativeProvider: any NativeWordPredicting
    @ObservationIgnored private let modelProvider: any ModelWordPredicting
    @ObservationIgnored private let language: () -> String
    @ObservationIgnored private let enabled: () -> Bool
    @ObservationIgnored private let shortcutsActive: () -> Bool
    @ObservationIgnored private let insert:
        (PredictionInsertion, FocusedKeyboardTarget) throws -> Void
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var displayedContext: PredictionContext?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var nativeWords: [String] = []
    @ObservationIgnored private var modelWords: [String] = []
    @ObservationIgnored private var nativePending = false
    @ObservationIgnored private var modelPending = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var nativeTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var modelTask: Task<Void, Never>?
    @ObservationIgnored private var pendingModel: (revision: Int, input: PredictionInput)?
    @ObservationIgnored private var lastAvailability: String?
    @ObservationIgnored private var automaticSpace: PredictionSpace?

    // MARK: - Initialization
    init(
        contextProvider: any PredictionContextProviding,
        nativeProvider: any NativeWordPredicting,
        modelProvider: any ModelWordPredicting,
        language: @escaping () -> String,
        enabled: @escaping () -> Bool,
        shortcutsActive: @escaping () -> Bool,
        debounce: Duration = .milliseconds(150),
        insert: @escaping (PredictionInsertion, FocusedKeyboardTarget) throws -> Void
    ) {
        self.contextProvider = contextProvider
        self.nativeProvider = nativeProvider
        self.modelProvider = modelProvider
        self.language = language
        self.enabled = enabled
        self.shortcutsActive = shortcutsActive
        self.debounce = debounce
        self.insert = insert
    }

    // MARK: - Availability
    var modelStatus: String {
        modelProvider.unavailableReason(language: language())
            ?? "On-device AI predictions are ready."
    }

    // MARK: - Lifecycle
    func start(polling: Bool = true) {
        guard !isRunning, enabled() else { return }
        isRunning = true
        nativeProvider.prewarm(language: language())
        contextProvider.startObserving { [weak self] in self?.scheduleRefresh() }
        refresh()
        if modelTask == nil, modelProvider.unavailableReason(language: language()) == nil {
            modelProvider.prewarm()
        }
        guard polling else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        isRunning = false
        pollTask?.cancel()
        pollTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        contextProvider.stopObserving()
        invalidate()
        // An uncancellable provider may still be finishing. Its worker owns cleanup.
        if modelTask == nil { modelProvider.reset() }
    }

    // MARK: - Context Refresh
    func refresh() {
        guard isRunning else { return }
        guard enabled() else {
            stop()
            return
        }
        guard !shortcutsActive() else {
            invalidate()
            return
        }
        let language = language()
        // Switching the spell checker's language takes a moment before it predicts.
        nativeProvider.prewarm(language: language)
        let started = ContinuousClock.now
        let next = contextProvider.capture(language: language)
        if next != nil { PredictionTiming.record("context", since: started) }
        if replaceAutomaticSpace(before: next) { return }
        let availability = modelProvider.unavailableReason(language: language)
        guard let next else {
            // A keypress may already have invalidated context while keeping its words.
            // Missing context must also clear that preserved presentation.
            invalidate()
            lastAvailability = availability
            return
        }
        guard needsRefresh || next != completionContext || availability != lastAvailability else {
            return
        }
        let sameSession =
            (completionContext ?? displayedContext).map { next.continuesPresentation(of: $0) }
            ?? false
        invalidate(keepingPresentation: sameSession)
        // Keep only preserved words that the new context can still accept.
        let acceptable = suggestions.filter { next.acceptance(for: $0) != nil }
        if acceptable != suggestions { suggestions = acceptable }
        typedPrefix = next.input.prefix
        lastAvailability = availability
        completionContext = next
        needsRefresh = false
        hasTextContext = true
        nativePending = true
        modelPending = availability == nil
        let revision = revision
        nativeTask = Task { [weak self, nativeProvider] in
            guard !Task.isCancelled else { return }
            let started = ContinuousClock.now
            let words = await nativeProvider.predictions(for: next.input)
            guard !Task.isCancelled, let self, self.revision == revision, self.isRunning else {
                return
            }
            PredictionTiming.record("native", since: started)
            self.nativePending = false
            self.nativeWords = next.input.validated(words)
            self.publish()
        }
        guard availability == nil else { return }
        debounceTask = Task { [weak self, debounce] in
            do { try await Task.sleep(for: debounce) }
            catch { return }
            guard let self, self.revision == revision, self.isRunning else { return }
            self.pendingModel = (revision, next.input)
            self.runPendingModel()
        }
    }

    func keyboardDidChange() {
        guard isRunning else { return }
        invalidate(keepingPresentation: true)
        // Posted keyboard events are applied asynchronously by the receiving application.
        scheduleRefresh(delay: .milliseconds(20))
    }

    private func scheduleRefresh(delay: Duration = .zero) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) }
            catch { return }
            self?.refresh()
        }
    }

    // MARK: - Model Worker
    private func runPendingModel() {
        guard modelTask == nil, let pendingModel, isRunning else { return }
        self.pendingModel = nil
        modelTask = Task { [weak self, modelProvider] in
            let started = ContinuousClock.now
            do {
                let words = try await modelProvider.predictions(for: pendingModel.input) {
                    [weak self] words in
                    guard !Task.isCancelled, let self, self.isRunning,
                        self.revision == pendingModel.revision
                    else { return }
                    let validWords = pendingModel.input.validated(words)
                    if self.modelWords.isEmpty, !validWords.isEmpty {
                        PredictionTiming.record("model-first", since: started)
                    }
                    self.modelWords = validWords
                    self.publish()
                }
                if !Task.isCancelled, let self, self.isRunning,
                    self.revision == pendingModel.revision
                {
                    PredictionTiming.record("model", since: started)
                    self.modelWords = pendingModel.input.validated(words)
                }
            }
            catch {
                // Native completions remain available on refusal, cancellation, or generation failure.
            }
            if let self, self.isRunning, self.revision == pendingModel.revision {
                self.modelPending = false
                self.publish()
            }
            modelProvider.reset()
            guard let self else { return }
            self.modelTask = nil
            if self.isRunning, self.enabled(),
                modelProvider.unavailableReason(language: self.language()) == nil
            {
                modelProvider.prewarm()
            }
            self.runPendingModel()
        }
    }

    // MARK: - Publication
    private func publish() {
        guard let context = completionContext else { return }
        // Native candidates arrive first and are ranked by typing frequency. Keep the
        // top few in place and let contextual AI words follow them.
        let leading = Self.leadingNativeSuggestions
        let ranked = nativeWords.prefix(leading) + modelWords + nativeWords.dropFirst(leading)
        let next = Array(
            context.input.validated(Array(ranked)).prefix(PredictionInput.maximumSuggestions)
        )
        guard !next.isEmpty || (!nativePending && !modelPending) else { return }
        suggestions = next
        displayedContext = context
    }

    private func invalidate(keepingPresentation: Bool = false) {
        revision += 1
        nativeTask?.cancel()
        nativeTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        modelTask?.cancel()
        pendingModel = nil
        needsRefresh = true
        if !keepingPresentation { completionContext = nil }
        nativeWords = []
        modelWords = []
        nativePending = false
        modelPending = false
        if !keepingPresentation {
            automaticSpace = nil
            typedPrefix = ""
            suggestions = []
            displayedContext = nil
            hasTextContext = false
        }
    }

    // MARK: - Prediction Spacing
    private func replaceAutomaticSpace(before next: PredictionContext?) -> Bool {
        guard let pending = automaticSpace else { return false }
        guard let next, next.source == .accessibility,
            next.target.hasSameFocus(as: pending.before.target),
            next.input.language == pending.before.input.language, next.input.isAtLineEnd
        else {
            automaticSpace = nil
            return false
        }
        // Posted input is asynchronous. Wait for the accepted word to appear, but
        // stop tracking if the user later deletes back to the original fragment.
        if pending.awaitingInsertion, next == pending.before { return false }
        if pending.isInserted(in: next) {
            automaticSpace?.awaitingInsertion = false
            return false
        }
        automaticSpace = nil
        guard let punctuation = pending.typedAfterSpace(in: next), !punctuation.isEmpty,
            punctuation.allSatisfy(PredictionInput.isSentencePunctuation),
            contextProvider.capture(language: language()) == next
        else { return false }

        // Replace only our space and the punctuation just typed. Revalidate the
        // complete field and cursor immediately before posting to the same app.
        invalidate(keepingPresentation: true)
        do {
            try insert(
                PredictionInsertion(
                    text: punctuation,
                    deleteBackwardCount: punctuation.count + 1
                ),
                next.target
            )
            scheduleRefresh(delay: .milliseconds(20))
            return true
        }
        catch { return false }
    }

    // MARK: - Sentence Completion Acceptance
    @discardableResult
    func acceptCompletion(_ suffix: String, context expected: PredictionContext) -> Bool {
        guard isRunning, enabled(), !shortcutsActive(), !suffix.isEmpty,
            contextProvider.capture(language: language()) == expected
        else { return false }
        invalidate()
        do {
            try insert(PredictionInsertion(text: suffix, deleteBackwardCount: 0), expected.target)
            scheduleRefresh(delay: .milliseconds(20))
            return true
        }
        catch { return false }
    }

    // MARK: - Acceptance
    func choice(for word: String) -> PredictionChoice? {
        guard isRunning, enabled(), !shortcutsActive(), suggestions.contains(word),
            let displayedContext,
            let current = contextProvider.capture(language: language()),
            current.continuesPresentation(of: displayedContext),
            current.acceptance(for: word) != nil
        else { return nil }
        // Displayed words remain usable while a new request is running. Capture the
        // current prefix at activation, then revalidate it immediately before insertion.
        return PredictionChoice(word: word, context: current)
    }

    /// Accepts a visible word, capturing and validating the field once before posting.
    @discardableResult
    func accept(word: String) -> Bool {
        guard let choice = choice(for: word) else { return false }
        return commit(choice.word, in: choice.context)
    }

    @discardableResult
    func accept(_ choice: PredictionChoice) -> Bool {
        guard isRunning, enabled(), !shortcutsActive(),
            let current = contextProvider.capture(language: language()),
            current == choice.context
        else {
            invalidate()
            return false
        }
        return commit(choice.word, in: current)
    }

    // MARK: - Insertion
    private func commit(_ word: String, in current: PredictionContext) -> Bool {
        guard let insertion = current.acceptance(for: word) else {
            invalidate()
            return false
        }
        // No suspension between revalidation and posting to the captured process.
        invalidate(keepingPresentation: true)
        automaticSpace = nil
        do {
            try insert(insertion, current.target)
            automaticSpace = PredictionSpace(insertion: insertion, context: current)
            scheduleRefresh(delay: .milliseconds(20))
            return true
        }
        catch { return false }
    }
}
