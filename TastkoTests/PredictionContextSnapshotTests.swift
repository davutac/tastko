import ApplicationServices
import Foundation
import Testing

@testable import Tastko

// MARK: - PredictionContextSnapshotTests
@MainActor
struct PredictionContextSnapshotTests {
    // MARK: - Terminal Selection Is Not the Caret
    @Test(arguments: ["Last login: yesterday\nuser@host % he", "% he", ""])
    func terminalScreenAndZeroSelectionUseTypingContext(_ screen: String) async throws {
        let fixture = PredictionSurfaceFixture(screen: screen)
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        try fixture.keyboard.type("he")
        fixture.service.refresh()
        let context = try #require(fixture.provider.capture(language: "en"))
        #expect(context.input.context == "he")
        #expect(context.input.prefix == "he")
        #expect(context.source != .accessibility)
        await eventually { fixture.service.suggestions == ["hello"] }
        let choice = try #require(fixture.service.choice(for: "hello"))
        #expect(fixture.service.accept(choice))
        #expect(fixture.insertions == [PredictionInsertion(text: "llo ", deleteBackwardCount: 0)])
        #expect(fixture.provider.capture(language: "en")?.input.context == "hello ")
        #expect(fixture.poster.text == ["he", "llo "])
    }

    // MARK: - Background Output and Invalid Caret Ranges
    @Test func terminalOutputAndPlaceholderCursorDoNotEraseTypedContext() async throws {
        let fixture = PredictionSurfaceFixture(screen: "Last login\n% ")
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        try fixture.keyboard.type("he")
        fixture.screen = "Build output arrived asynchronously\n% he"
        // Longer than the normal AX cursor acknowledgment deadline.
        try await Task.sleep(for: .milliseconds(200))
        fixture.service.refresh()
        #expect(fixture.provider.capture(language: "en")?.input.context == "he")
        try fixture.keyboard.tap(KeyStroke(.delete))
        #expect(fixture.provider.capture(language: "en")?.input.prefix == "h")
        try fixture.keyboard.tap(KeyStroke(.leftArrow))
        #expect(fixture.provider.capture(language: "en") == nil)
    }

    // MARK: - Opaque Terminal Targets
    @Test(arguments: [AccessibilityFocusRoute.window, .application])
    func opaqueSurfacesPredictWithoutAnyTextElementOrCursor(_ route: AccessibilityFocusRoute)
        async throws
    {
        let fixture = PredictionSurfaceFixture(screen: nil)
        fixture.selection = nil
        let application = AXUIElementCreateApplication(42)
        fixture.target = FocusedKeyboardTarget(
            processIdentifier: 42,
            applicationName: "Custom Surface",
            applicationElement: application,
            focusedTextElement: nil,
            focusedWindow: route == .window ? AXUIElementCreateApplication(43) : nil,
            route: route
        )
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        try fixture.keyboard.type("he")
        fixture.service.refresh()
        await eventually { fixture.service.suggestions == ["hello"] }
        #expect(fixture.service.accept(try #require(fixture.service.choice(for: "hello"))))
        #expect(fixture.poster.text == ["he", "llo "])
        #expect(fixture.provider.capture(language: "en")?.input.context == "hello ")
    }

    // MARK: - Selection and Native Fields
    @Test(arguments: [false, true])
    func realSelectionsSuspendPredictionsAndEditableFieldsUseAX(_ isValueSettable: Bool) {
        let fixture = PredictionSurfaceFixture(screen: "selected text")
        fixture.isValueSettable = isValueSettable
        fixture.selection = AccessibilityTextRange(location: 0, length: 8)
        fixture.provider.startObserving({})
        defer { fixture.provider.stopObserving() }
        #expect(fixture.provider.capture(language: "en") == nil)
        fixture.provider.prepareForInput()
        fixture.provider.didPostText("he")
        #expect(fixture.provider.capture(language: "en") == nil)
        fixture.isValueSettable = true
        fixture.screen = "search"
        fixture.selection = AccessibilityTextRange(location: 6, length: 0)
        let context = fixture.provider.capture(language: "en")
        #expect(context?.source == .accessibility)
        #expect(context?.input.prefix == "search")
    }

    @Test func ordinaryTextAreaAtWordStartStaysIneligible() {
        let fixture = PredictionSurfaceFixture(screen: "hello")
        fixture.isValueSettable = true
        fixture.provider.startObserving({})
        defer { fixture.provider.stopObserving() }
        #expect(fixture.provider.capture(language: "en") == nil)
        fixture.provider.prepareForInput()
        fixture.provider.didPostText("he")
        #expect(fixture.provider.capture(language: "en") == nil)
    }

    // MARK: - Incomplete Editable Context
    @Test(arguments: [true, false])
    func missingTextOrCursorUsesTypingContext(_ hasText: Bool) async throws {
        let fixture = PredictionSurfaceFixture(screen: hasText ? "he" : nil)
        fixture.isValueSettable = true
        fixture.selection = hasText ? nil : AccessibilityTextRange(location: 0, length: 0)
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        try fixture.keyboard.type("he")
        #expect(fixture.provider.capture(language: "en")?.input.context == "he")
        #expect(fixture.provider.capture(language: "en")?.source != .accessibility)
    }

    // MARK: - Accessibility Recovery
    @Test func editableContextReplacesTheBufferAndInvalidatesItsChoice() async throws {
        let fixture = PredictionSurfaceFixture(screen: "% ")
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        try fixture.keyboard.type("he")
        fixture.service.refresh()
        await eventually { fixture.service.suggestions == ["hello"] }
        let choice = try #require(fixture.service.choice(for: "hello"))
        fixture.isValueSettable = true
        fixture.screen = "help"
        fixture.selection = AccessibilityTextRange(location: 4, length: 0)
        #expect(fixture.provider.capture(language: "en")?.input.prefix == "help")
        #expect(fixture.provider.capture(language: "en")?.source == .accessibility)
        #expect(!fixture.service.accept(choice))
        fixture.isValueSettable = false
        #expect(fixture.provider.capture(language: "en") == nil)
        #expect(fixture.poster.text == ["he"])
    }

    @Test func selectedTextWithoutARangeIsIneligible() {
        let snapshot = PredictionContextSnapshot(
            target: predictionContext("").target,
            value: FocusedTextValue(
                text: nil,
                selectedText: "selection",
                selectedRange: nil,
                numberOfCharacters: nil
            ),
            language: "en",
            isValueSettable: false
        )
        guard case .ineligible = snapshot else {
            Issue.record("Selection must suspend fallback even without a range")
            return
        }
    }

    // MARK: - Focus Changes
    @Test func switchingTerminalPanesRejectsThePreviousChoice() async throws {
        let fixture = PredictionSurfaceFixture(screen: "% ")
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        try fixture.keyboard.type("he")
        fixture.service.refresh()
        await eventually { fixture.service.suggestions == ["hello"] }
        let choice = try #require(fixture.service.choice(for: "hello"))
        fixture.target = predictionContext("", elementID: 2).target
        #expect(!fixture.service.accept(choice))
        #expect(fixture.provider.capture(language: "en") == nil)
        #expect(fixture.poster.text == ["he"])
    }
}

// MARK: - Surface Capability Fixture
// SurfaceView_AppKit.swift exposes AXValue as cachedScreenContents and
// AXSelectedTextRange as selectedRange(), which returns NSRange() with no selection.
// https://github.com/ghostty-org/ghostty/blob/v1.3.1/macos/Sources/Ghostty/Surface%20View/SurfaceView_AppKit.swift
@MainActor
private final class PredictionSurfaceFixture: KeyboardTargetResolving {
    var target = predictionContext("").target
    var screen: String?
    var isValueSettable = false
    var selection: AccessibilityTextRange? = AccessibilityTextRange(location: 0, length: 0)
    let native = TestNativeProvider()
    let model = TestModelProvider()
    var insertions: [PredictionInsertion] = []
    let poster = PredictionSurfaceEventPoster()

    lazy var keyboard: KeyboardService = {
        let keyboard = KeyboardService(targetResolver: self, eventPoster: poster)
        keyboard.typingObserver = provider
        return keyboard
    }()

    lazy var provider = AccessibilityPredictionContextProvider(
        observesSystem: false,
        inputSource: { "com.apple.keylayout.US" },
        snapshot: { [unowned self] language in
            PredictionContextSnapshot(
                target: target,
                value: FocusedTextValue(
                    text: screen,
                    selectedText: nil,
                    selectedRange: selection,
                    numberOfCharacters: screen?.utf16.count
                ),
                language: language,
                isValueSettable: isValueSettable
            )
        }
    )
    lazy var service = TextPredictionService(
        contextProvider: provider,
        nativeProvider: native,
        modelProvider: model,
        language: { "en" },
        enabled: { true },
        shortcutsActive: { false },
        insert: { [unowned self] insertion, target in
            insertions.append(insertion)
            try keyboard.insertPrediction(
                insertion.text,
                deletingBackward: insertion.deleteBackwardCount,
                into: target
            )
        }
    )

    // MARK: - Initialization
    init(screen: String?) {
        self.screen = screen
        native.immediateWords = ["hello"]
        model.reason = "Unavailable"
    }

    // MARK: - Keyboard Target
    func focusedKeyboardTarget() throws -> FocusedKeyboardTarget { target }
}

// MARK: - Surface Event Fixture
@MainActor
private final class PredictionSurfaceEventPoster: KeyboardEventPosting {
    var text: [String] = []

    // MARK: - Posting
    func postText(_ text: String, to target: FocusedKeyboardTarget) throws {
        self.text.append(text)
    }
    func replacePrefix(_ count: Int, with text: String, to target: FocusedKeyboardTarget) throws {
        Issue.record("Fallback predictions must not delete existing text")
    }
    func postTextToSystemFocus(_ text: String) throws {
        Issue.record("Unexpected system text route")
    }
    func postKey(_ key: Key, modifiers: KeyModifiers, keyDown: Bool) throws {}
}
