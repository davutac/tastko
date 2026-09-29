import ApplicationServices
import Foundation
import Testing

@testable import Tastko

// MARK: - Prediction Fixtures
@MainActor
final class PredictionFixture {
    let source = TestPredictionContextProvider()
    let native = TestNativeProvider()
    let model = TestModelProvider()
    var enabled = true
    var language = "en"
    var shortcuts = false
    var insertions: [String] = []
    var deletions: [Int] = []
    var deliveredPID: pid_t?
    var failsInsertion = false
    let debounce: Duration

    lazy var service = TextPredictionService(
        contextProvider: source,
        nativeProvider: native,
        modelProvider: model,
        language: { [unowned self] in language },
        enabled: { [unowned self] in enabled },
        shortcutsActive: { [unowned self] in shortcuts },
        debounce: debounce,
        insert: { [unowned self] insertion, target in
            if failsInsertion { throw KeyboardServiceError.eventCreationFailed }
            insertions.append(insertion.text)
            deletions.append(insertion.deleteBackwardCount)
            deliveredPID = target.processIdentifier
        }
    )

    // MARK: - Initialization
    init(debounce: Duration = .zero) { self.debounce = debounce }
}

@MainActor
final class TestPredictionContextProvider: PredictionContextProviding {
    var context: PredictionContext? = predictionContext("he")
    var observing = false

    // MARK: - Provider
    func capture(language: String) -> PredictionContext? {
        guard let context, let text = context.value.text, let range = context.value.selectedRange,
            let input = PredictionInput(text: text, range: range, language: language)
        else { return nil }
        return PredictionContext(target: context.target, value: context.value, input: input)
    }
    func startObserving(_ changed: @escaping @MainActor () -> Void) { observing = true }
    func stopObserving() { observing = false }
}

@MainActor
final class TestNativeProvider: NativeWordPredicting {
    var immediateWords: [String]?
    var requests: [CheckedContinuation<[String], Never>?] = []
    var prewarmedLanguages: [String] = []

    // MARK: - Provider
    func prewarm(language: String) {
        if prewarmedLanguages.last != language { prewarmedLanguages.append(language) }
    }
    func predictions(for input: PredictionInput) async -> [String] {
        if let immediateWords { return immediateWords }
        return await withCheckedContinuation { requests.append($0) }
    }
    func finish(_ index: Int, words: [String]) {
        requests[index]?.resume(returning: words)
        requests[index] = nil
    }
    func finishAll() {
        for index in requests.indices { finish(index, words: []) }
    }
}

@MainActor
final class TestModelProvider: ModelWordPredicting {
    var requests: [CheckedContinuation<[String], any Error>?] = []
    var updates: [@MainActor ([String]) -> Void] = []
    var inputs: [PredictionInput] = []
    var reason: String?
    var active = 0
    var maximumActive = 0
    var resetCount = 0

    // MARK: - Provider
    func unavailableReason(language: String) -> String? { reason }
    func prewarm() {}
    func reset() { resetCount += 1 }
    func predictions(
        for input: PredictionInput,
        update: @escaping @MainActor ([String]) -> Void
    ) async throws -> [String] {
        active += 1
        updates.append(update)
        maximumActive = max(maximumActive, active)
        inputs.append(input)
        defer { active -= 1 }
        return try await withCheckedThrowingContinuation { requests.append($0) }
    }
    func finish(_ index: Int, words: [String]) {
        requests[index]?.resume(returning: words)
        requests[index] = nil
    }
    func fail(_ index: Int) {
        requests[index]?.resume(throwing: CancellationError())
        requests[index] = nil
    }
}

// MARK: - Context Fixture
@MainActor
func predictionContext(
    _ text: String,
    elementID: pid_t = 1,
    cursor: Int? = nil,
    selectionLength: Int = 0
) -> PredictionContext {
    let element = AXUIElementCreateApplication(elementID)
    let range = AccessibilityTextRange(
        location: cursor ?? text.utf16.count,
        length: selectionLength
    )
    return PredictionContext(
        target: FocusedKeyboardTarget(
            processIdentifier: 42,
            applicationName: "Fixture",
            applicationElement: element,
            focusedTextElement: element,
            focusedWindow: nil,
            route: .textElement
        ),
        value: FocusedTextValue(
            text: text,
            selectedText: nil,
            selectedRange: range,
            numberOfCharacters: text.utf16.count
        ),
        input: PredictionInput(
            text: text,
            range: AccessibilityTextRange(location: text.utf16.count, length: 0),
            language: "en"
        )!
    )
}

// MARK: - Async Synchronization
@MainActor
func eventually(_ condition: () -> Bool) async {
    for _ in 0..<200 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(2))
    }
    #expect(condition(), "Timed out waiting for the prediction pipeline")
}
