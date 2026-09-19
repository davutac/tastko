import Foundation
import Testing

@testable import Tastko

// MARK: - Prediction Text Coordinates Tests
@MainActor
struct PredictionTextCoordinatesTests {
    // MARK: - ChatGPT Regression
    @Test func omittedNewlineStillSuggestsAndInsertsOnlyTheLastWordSuffix() async throws {
        let text = "hello, hel\nhel"
        let value = FocusedTextValue(
            text: text,
            selectedText: nil,
            selectedRange: AccessibilityTextRange(location: 13, length: 0),
            numberOfCharacters: 14
        )
        let snapshot = PredictionContextSnapshot(
            target: predictionContext(text).target,
            value: value,
            language: "en",
            isValueSettable: true,
            textForRange: { range in
                // Captured ChatGPT AXStringForRange behavior, not AXValue offsets.
                guard range == AccessibilityTextRange(location: 0, length: 13) else {
                    return nil
                }
                return "hello, helhel"
            }
        )
        guard case .readable(let context) = snapshot else {
            Issue.record("The end-of-line fragment must remain eligible for predictions")
            return
        }
        #expect(context.input.context == text)
        #expect(context.input.prefix == "hel")
        #expect(context.input.isAtEnd)
        #expect(context.value.selectedRange?.location == 14)

        let fixture = PredictionFixture()
        fixture.source.context = context
        fixture.native.immediateWords = ["hello"]
        fixture.model.reason = "Unavailable"
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.service.suggestions == ["hello"] }
        let choice = try #require(fixture.service.choice(for: "hello"))
        #expect(fixture.service.accept(choice))
        #expect(fixture.insertions == ["lo "])
        #expect(fixture.deletions == [0])
    }

    // MARK: - Unicode and Multiple Paragraphs
    @Test(arguments: ["hello, hel\nhel", "one\ntwo\nhel", "😀\r\nhe\u{301}\nhel", "one\u{2028}hel"])
    func mapsOmittedBreaksWithoutChangingText(_ text: String) throws {
        let compact = text.filter { !$0.isNewline }
        let resolved = try #require(
            PredictionTextCoordinates.selection(
                in: text,
                range: AccessibilityTextRange(location: compact.utf16.count, length: 0),
                textForRange: { range in
                    range.length <= compact.utf16.count
                        ? (compact as NSString).substring(to: range.length) : nil
                }
            )
        )
        #expect(resolved.location == text.utf16.count)
        let input = try #require(PredictionInput(text: text, range: resolved, language: "en"))
        #expect(input.context == text)
        #expect(input.prefix == "hel")
    }

    // MARK: - Native and Unsupported Fields
    @Test(arguments: [true, false])
    func preservesOrdinaryMultilineCoordinates(_ supportsRanges: Bool) {
        let text = "hello\nhel"
        let range = AccessibilityTextRange(location: text.utf16.count, length: 0)
        #expect(
            PredictionTextCoordinates.selection(
                in: text,
                range: range,
                textForRange: { requested in
                    supportsRanges ? (text as NSString).substring(to: requested.length) : nil
                }
            ) == range
        )
    }

    @Test func doesNotProbeSingleLineText() {
        let range = AccessibilityTextRange(location: 3, length: 0)
        #expect(
            PredictionTextCoordinates.selection(in: "hel", range: range) { _ in
                Issue.record("Single-line fields need no coordinate mapping")
                return nil
            } == range
        )
    }

    // MARK: - Ambiguous and Invalid Positions
    @Test(arguments: [5, 9, -1])
    func neverGuessesAtOmittedBreaksOrInvalidOffsets(_ location: Int) {
        let text = "hello\nhel"
        let resolved = PredictionTextCoordinates.selection(
            in: text,
            range: AccessibilityTextRange(location: location, length: 0),
            textForRange: { $0.length == 8 ? "hellohel" : nil }
        )
        let input = resolved.flatMap { PredictionInput(text: text, range: $0, language: "en") }
        #expect(input == nil)
    }

    @Test func genuineMidWordCursorStaysIneligibleAfterMapping() {
        let text = "hello\nhel"
        let resolved = PredictionTextCoordinates.selection(
            in: text,
            range: AccessibilityTextRange(location: 7, length: 0),
            textForRange: { $0.length == 8 ? "hellohel" : nil }
        )
        #expect(resolved?.location == 8)
        #expect(resolved.flatMap { PredictionInput(text: text, range: $0, language: "en") } == nil)
    }

    @Test func unrelatedRangeTextDoesNotShiftCursor() {
        let range = AccessibilityTextRange(location: 9, length: 0)
        #expect(
            PredictionTextCoordinates.selection(in: "hello\nhel", range: range) { _ in
                "different"
            } == range
        )
    }
}
