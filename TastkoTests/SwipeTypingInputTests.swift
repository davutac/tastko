import CoreGraphics
import Defaults
import Foundation
import Testing

@testable import Tastko

// MARK: - SwipeTypingInputTests
@Suite(.serialized)
@MainActor
struct SwipeTypingInputTests {
    private let poster = FakeKeyboardEventPoster()
    private let keyboard: KeyboardService

    init() {
        keyboard = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(target: keyboardServiceTarget()),
            eventPoster: poster
        )
    }

    // MARK: - Letters
    @Test func letterTypesWhenReleasedWhileSwipeTypingIsOn() {
        let controller = makeController()
        let a = letterButton("a")
        controller.pointerDown(a, at: center(of: a), time: 0)
        controller.press(a, with: .leftClick)
        #expect(poster.events.isEmpty)
        controller.release(a)
        #expect(poster.events == [.key(.a, [], true), .key(.a, [], false)])
    }

    @Test func letterTypesOnPressWithoutAPointerPosition() {
        let controller = makeController()
        let a = letterButton("a")
        controller.press(a, with: .leftClick)
        controller.release(a)
        #expect(poster.events == [.key(.a, [], true), .key(.a, [], false)])
    }

    @Test func letterSlippingOffItsKeyStillTypesButACancelDoesNot() {
        let controller = makeController()
        let a = letterButton("a")
        controller.pointerDown(a, at: center(of: a), time: 0)
        controller.press(a, with: .leftClick)
        controller.cancel(a)
        #expect(poster.events.isEmpty)
        let origin = center(of: a)
        controller.pointerDown(a, at: origin, time: 1)
        controller.press(a, with: .leftClick)
        let offKey = CGPoint(x: origin.x + 25, y: origin.y)
        #expect(controller.pointerMoved(a, to: offKey, time: 1.1) == .tracking)
        controller.pointerUp(a, at: offKey, time: 1.2, inside: false)
        #expect(poster.events == [.key(.a, [], true), .key(.a, [], false)])
    }

    // MARK: - Swiped Words
    @Test func swipedWordsTypeWithASpaceBetweenWithoutFieldText() throws {
        let controller = makeController()
        try swipe("hello", with: controller)
        try swipe("world", with: controller)
        #expect(postedTexts == ["hello", " world"])
    }

    @Test func swipedWordGoesThroughTheFieldWhenItCanBeRead() throws {
        var inserted: [(String, [String])] = []
        let controller = makeController(
            swipeContext: { predictionContext("Say") },
            insertSwipedWord: { word, alternatives, _ in
                inserted.append((word, alternatives))
                return true
            }
        )
        try swipe("hello", with: controller)
        #expect(inserted.map(\.0) == ["hello"])
        #expect(inserted.first?.1.isEmpty == false)
        #expect(poster.events.isEmpty)
    }

    @Test func shiftOrARightClickCapitalisesTheSwipedWord() throws {
        let controller = makeController()
        let shift = PanelEditorButton(
            id: "shift",
            frame: .zero,
            title: "shift",
            secondaryTitle: nil,
            fontSize: 12,
            backgroundColor: nil,
            foregroundColor: nil,
            shape: .rectangle,
            primaryAction: .modifier(.leftShift),
            secondaryAction: .none,
            pressBehavior: .oneShot
        )
        controller.press(shift, with: .leftClick)
        #expect(keyboard.latchedModifiers == [.leftShift])
        try swipe("hello", with: controller)
        #expect(keyboard.latchedModifiers.isEmpty)
        try swipe("world", with: controller, trigger: .rightClick)
        #expect(postedTexts == ["Hello", " World"])
    }

    // MARK: - Fixtures
    private var postedTexts: [String] {
        poster.events.compactMap { event in
            guard case .text(let text, _, _) = event else { return nil }
            return text
        }
    }

    private func makeController(
        swipeContext: @escaping () -> PredictionContext? = { nil },
        insertSwipedWord: @escaping (String, [String], PredictionContext) -> Bool = { _, _, _ in
            false
        }
    ) -> KeyInputController {
        let suite = UserDefaults(suiteName: "SwipeTypingInputTests-\(UUID().uuidString)")!
        let swipe = SwipeTypingController(
            enabled: { true },
            inputAllowed: { true },
            language: { ("com.apple.keylayout.US", "en") },
            letter: { SwipeGrid.letter(for: $0) },
            vocabulary: { SwipeVocabulary(languageCode: $0) }
        )
        swipe.configure(panel: SwipeGrid.panel)
        return KeyInputController(
            keyboard: keyboard,
            languages: KeyboardLanguageService(),
            sounds: SoundService(
                soundPlayer: FakeSystemSoundPlayer(soundID: 7),
                preference: Defaults.Key("buttonSound", default: .keyClick, suite: suite)
            ),
            swipe: swipe,
            swipeContext: swipeContext,
            insertSwipedWord: insertSwipedWord
        )
    }

    private func letterButton(_ id: String) -> PanelEditorButton {
        SwipeGrid.buttons.first { $0.id == id }!
    }

    private func center(of button: PanelEditorButton) -> CGPoint {
        CGPoint(x: button.frame.midX, y: button.frame.midY)
    }

    /// Presses `word`'s first letter, drags through its keys, and releases.
    private func swipe(
        _ word: String,
        with controller: KeyInputController,
        trigger: KeyActionTrigger = .leftClick
    ) throws {
        let map = try #require(SwipeKeyMap(letterKeys: SwipeGrid.qwerty))
        let stroke = SwipeGrid.stroke(word, on: map)
        let first = letterButton(String(try #require(word.first)))
        controller.pointerDown(first, at: stroke.points[0], time: 0)
        controller.press(first, with: trigger)
        for (point, time) in zip(stroke.points, stroke.times).dropFirst() {
            _ = controller.pointerMoved(first, to: point, time: time)
        }
        let end = try #require(stroke.points.last)
        controller.pointerUp(first, at: end, time: (stroke.times.last ?? 0) + 0.01, inside: false)
    }
}

// MARK: - SwipeAlternativesTests
@MainActor
struct SwipeAlternativesTests {
    @Test func swipedWordGoesInSpacedAndOffersItsOtherReadings() throws {
        let fixture = PredictionFixture()
        fixture.model.reason = "Unavailable"
        fixture.native.immediateWords = []
        fixture.source.context = predictionContext("Say")
        #expect(fixture.service.swipeContext() == nil)
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }

        let context = try #require(fixture.service.swipeContext())
        #expect(
            fixture.service.insertSwipedWord(
                "hello",
                alternatives: ["hells", "jello"],
                context: context
            )
        )
        #expect(fixture.insertions == [" hello "])
        #expect(fixture.service.suggestions == ["hells", "jello"])

        fixture.source.context = predictionContext("Say hello ")
        fixture.service.refresh()
        #expect(fixture.service.suggestions == ["hells", "jello"])

        #expect(fixture.service.accept(word: "jello"))
        #expect(fixture.insertions.last == " jello ")
        #expect(fixture.deletions.last == 7)
        #expect(fixture.service.suggestions == ["hello", "hells"])

        fixture.source.context = predictionContext("Say jello w")
        fixture.service.keyboardDidChange()
        fixture.service.refresh()
        #expect(!fixture.service.suggestions.contains("hells"))
    }

    @Test func swipedWordTakesTheSpaceItsPlaceNeeds() throws {
        let afterSpace = try #require(predictionContext("Say ").input.swipedWordParts("hello"))
        #expect(afterSpace.text == "hello ")
        let afterFragment = try #require(predictionContext("Sa").input.swipedWordParts("hello"))
        #expect(afterFragment.text == " hello ")
        let afterParenthesis = try #require(predictionContext("(").input.swipedWordParts("hello"))
        #expect(afterParenthesis.text == "hello ")
        let empty = try #require(predictionContext("").input.swipedWordParts("hello"))
        #expect(empty.text == "hello ")
        let typographic = try #require(predictionContext("it’s ").input.swipedWordParts("I'm"))
        #expect(typographic.word == "I’m")
    }
}
