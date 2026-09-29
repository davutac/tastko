import AppKit
import ApplicationServices
import Foundation
import Testing

@testable import Tastko

// MARK: - PredictionFallbackTests
@MainActor
struct PredictionFallbackTests {
    // MARK: - Empty Buffer Presentation
    @Test(arguments: [true, false])
    func emptyBufferClearsWordsAfterDeletionOrReset(_ deleteLastCharacter: Bool) async {
        let fixture = FallbackFixture()
        fixture.native.immediateWords = ["hello"]
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        #expect(fixture.service.suggestions.isEmpty)
        fixture.type("h")
        fixture.service.refresh()
        await eventually { fixture.service.suggestions == ["hello"] }
        if deleteLastCharacter {
            fixture.provider.prepareForInput()
            fixture.provider.didPostKey(KeyStroke(.delete))
        }
        else {
            fixture.provider.resetTypingSession()
        }
        fixture.service.keyboardDidChange()
        fixture.service.refresh()
        #expect(fixture.context == nil)
        #expect(fixture.service.suggestions.isEmpty)
        #expect(!fixture.service.hasTextContext)
    }

    // MARK: - Eligibility and Lifecycle
    @Test func fallsBackOnlyForUnreadableContextsAndDiscardsStateOnStop() {
        let fixture = FallbackFixture()
        fixture.provider.startObserving({})
        fixture.type("he")
        #expect(fixture.context?.input.context == "he")
        fixture.snapshot = .readable(predictionContext("actual text"))
        #expect(fixture.context?.source == .accessibility)
        #expect(fixture.context?.input.context == "actual text")
        fixture.snapshot = .unreadable(fixture.target, selection: nil)
        #expect(fixture.context == nil)
        fixture.type("fresh")
        fixture.snapshot = .ineligible
        #expect(fixture.context == nil)
        fixture.type("must not retain")
        fixture.snapshot = .unreadable(fixture.target, selection: nil)
        #expect(fixture.context == nil)
        fixture.type("before stop")
        fixture.provider.stopObserving()
        fixture.type("while stopped")
        fixture.provider.startObserving({})
        #expect(fixture.context == nil)
        fixture.provider.stopObserving()
    }

    @Test func rejectsFocusChangesDuringPostingAndResetsOnInputSourceChanges() {
        let fixture = FallbackFixture()
        fixture.provider.startObserving({})
        defer { fixture.provider.stopObserving() }
        fixture.type("he")
        fixture.provider.prepareForInput()
        fixture.snapshot = .unreadable(predictionContext("", elementID: 2).target, selection: nil)
        fixture.provider.didPostText("llo")
        #expect(fixture.context == nil)
        fixture.type("next")
        fixture.inputSource = "de"
        #expect(fixture.context == nil)
    }

    // MARK: - Real Keyboard Delivery Pipeline
    @Test func heldBackspaceClearsBufferAndSuggestions() async throws {
        let fixture = FallbackFixture()
        fixture.native.immediateWords = ["hello"]
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        let keyboard = KeyboardService(targetResolver: fixture, eventPoster: FallbackEventPoster())
        keyboard.typingObserver = fixture.provider
        keyboard.inputDidChange = { fixture.service.keyboardDidChange() }
        try keyboard.type("hel")
        fixture.service.refresh()
        await eventually { fixture.service.suggestions == ["hello"] }

        let token = try keyboard.beginPress(KeyStroke(.delete))
        #expect(fixture.context?.input.context == "he")
        try keyboard.repeatPress(token)
        #expect(fixture.context?.input.context == "h")
        try keyboard.repeatPress(token)
        try keyboard.endPress(token)
        fixture.service.refresh()
        #expect(fixture.context == nil)
        #expect(fixture.service.completionContext == nil)
        #expect(fixture.service.suggestions.isEmpty)
        #expect(!fixture.service.hasTextContext)
    }

    @Test func ownTaggedEventsPreserveContextAndExternalInputClearsIt() throws {
        let fixture = FallbackFixture()
        fixture.provider.startObserving({})
        defer { fixture.provider.stopObserving() }
        fixture.type("he")
        let observation = PredictionContextObservation(
            changed: {},
            reset: fixture.provider.resetTypingSession
        )
        let own = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        own.setIntegerValueField(
            .eventSourceUserData,
            value: CGKeyboardEventPoster.predictionEventTag
        )
        observation.externalInput(try #require(NSEvent(cgEvent: own)))
        #expect(fixture.context?.input.prefix == "he")
        let physical = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        observation.externalInput(try #require(NSEvent(cgEvent: physical)))
        #expect(fixture.context == nil)
        fixture.type("fresh")
        let click = try #require(
            CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: .zero,
                mouseButton: .left
            )
        )
        observation.externalInput(try #require(NSEvent(cgEvent: click)))
        #expect(fixture.context == nil)
    }

    @Test func postedTextAndBackspaceReachFallbackAndFailuresClearIt() async throws {
        let fixture = FallbackFixture()
        fixture.provider.startObserving({})
        _ = fixture.context
        defer { fixture.provider.stopObserving() }
        let poster = FallbackEventPoster()
        let keyboard = KeyboardService(targetResolver: fixture, eventPoster: poster)
        keyboard.typingObserver = fixture.provider
        try keyboard.type("hel")
        try keyboard.tap(KeyStroke(.delete))
        #expect(fixture.context?.input.prefix == "he")
        try keyboard.tap(KeyStroke(.leftArrow))
        #expect(fixture.context == nil)
        try keyboard.type("fresh")
        poster.fails = true
        #expect(throws: KeyboardServiceError.self) { try keyboard.type("failure") }
        #expect(fixture.context == nil)
        poster.fails = false
        try keyboard.type("before lock")
        keyboard.setScreenLocked(true, allowsInput: true)
        #expect(fixture.context == nil)
    }

    // MARK: - Prediction Acceptance
    @Test func acceptsSuffixAndNextWordAndKeepsBufferInSyncWithoutPunctuationRewrites() async throws
    {
        let fixture = FallbackFixture()
        fixture.native.immediateWords = ["hello"]
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        fixture.type("he")
        fixture.service.refresh()
        await eventually { fixture.service.suggestions == ["hello"] }
        let choice = try #require(fixture.service.choice(for: "hello"))
        #expect(fixture.service.accept(choice))
        #expect(fixture.insertions == [PredictionInsertion(text: "llo ", deleteBackwardCount: 0)])
        #expect(fixture.context?.input.context == "hello ")
        fixture.native.immediateWords = ["world"]
        fixture.service.refresh()
        await eventually { fixture.service.suggestions == ["world"] }
        #expect(fixture.service.accept(try #require(fixture.service.choice(for: "world"))))
        #expect(fixture.context?.input.context == "hello world ")
        fixture.type(".")
        fixture.service.refresh()
        #expect(fixture.insertions.count == 2)
        #expect(fixture.context?.input.context == "hello world .")
    }

    @Test func staleChoicesAndOldVisibleWordsCannotRewriteFallbackText() async throws {
        let fixture = FallbackFixture()
        fixture.native.immediateWords = ["hello"]
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        fixture.type("he")
        fixture.service.refresh()
        await eventually { fixture.service.suggestions == ["hello"] }
        let oldChoice = try #require(fixture.service.choice(for: "hello"))
        fixture.type("x")
        #expect(fixture.service.choice(for: "hello") == nil)
        #expect(!fixture.service.accept(oldChoice))
        #expect(fixture.insertions.isEmpty)
        fixture.provider.resetTypingSession()
        fixture.type("he")
        #expect(!fixture.service.accept(oldChoice))
        #expect(fixture.insertions.isEmpty)
    }

    @Test func delayedResultsCannotCrossResetEvenWithTheSameText() async {
        let fixture = FallbackFixture()
        fixture.service.start(polling: false)
        defer {
            fixture.service.stop()
            fixture.native.finishAll()
        }
        fixture.type("he")
        fixture.service.refresh()
        await eventually { fixture.native.requests.count == 1 }
        fixture.provider.resetTypingSession()
        fixture.type("he")
        fixture.service.refresh()
        await eventually { fixture.native.requests.count == 2 }
        fixture.native.finish(0, words: ["hello"])
        fixture.native.finish(1, words: ["help"])
        await eventually { fixture.service.suggestions == ["help"] }
    }
}

// MARK: - Fallback Fixtures
@MainActor
private final class FallbackFixture: KeyboardTargetResolving {
    let target = predictionContext("").target
    var snapshot: PredictionContextSnapshot
    var inputSource = "en"
    let native = TestNativeProvider()
    let model = TestModelProvider()
    var insertions: [PredictionInsertion] = []

    lazy var provider = AccessibilityPredictionContextProvider(
        observesSystem: false,
        inputSource: { [unowned self] in inputSource },
        snapshot: { [unowned self] _ in snapshot }
    )
    lazy var service = TextPredictionService(
        contextProvider: provider,
        nativeProvider: native,
        modelProvider: model,
        language: { "en" },
        enabled: { true },
        shortcutsActive: { false },
        insert: { [unowned self] insertion, _ in
            insertions.append(insertion)
            type(insertion.text)
        }
    )
    var context: PredictionContext? { provider.capture(language: "en") }

    // MARK: - Initialization
    init() {
        snapshot = .unreadable(target, selection: nil)
        model.reason = "Unavailable"
    }

    // MARK: - Delivery
    func type(_ text: String) {
        _ = context
        provider.prepareForInput()
        provider.didPostText(text)
    }
    func focusedKeyboardTarget() throws -> FocusedKeyboardTarget { target }
}

@MainActor
private final class FallbackEventPoster: KeyboardEventPosting {
    var fails = false

    // MARK: - Posting
    func postText(_ text: String, to target: FocusedKeyboardTarget) throws {
        if fails { throw KeyboardServiceError.eventCreationFailed }
    }
    func replacePrefix(_ count: Int, with text: String, to target: FocusedKeyboardTarget) throws {}
    func postTextToSystemFocus(_ text: String) throws {}
    func postKey(_ key: Key, modifiers: KeyModifiers, keyDown: Bool) throws {}
}
