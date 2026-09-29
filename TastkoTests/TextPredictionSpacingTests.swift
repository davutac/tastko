import Testing

@testable import Tastko

// MARK: - TextPredictionSpacingTests
@MainActor
struct TextPredictionSpacingTests {
    // MARK: - Prediction Spacing
    @Test(arguments: [",", ".", "!", "?", ";", ":", "…", "?!"])
    func punctuationReplacesOnlyThePredictionSpace(_ punctuation: String) async throws {
        let fixture = try await acceptedPrediction()
        defer { fixture.service.stop() }

        fixture.source.context = predictionContext("hello " + punctuation)
        fixture.service.keyboardDidChange()
        fixture.service.refresh()

        #expect(fixture.insertions == ["llo ", punctuation])
        #expect(fixture.deletions == [0, punctuation.count + 1])
        #expect(fixture.deliveredPID == 42)
        let result =
            String(("hello " + punctuation).dropLast(fixture.deletions[1]))
            + fixture.insertions[1]
        #expect(result == "hello" + punctuation)
        // A receiving app may still expose its previous value after event delivery.
        fixture.service.refresh()
        #expect(fixture.insertions.count == 2)
    }

    @Test func nextPredictionAddsSpaceAfterCorrectedPunctuation() async throws {
        let fixture = try await acceptedPrediction()
        defer { fixture.service.stop() }
        fixture.source.context = predictionContext("hello ,")
        fixture.service.refresh()
        #expect(fixture.insertions == ["llo ", ","])
        fixture.native.immediateWords = ["world"]
        fixture.source.context = predictionContext("hello,")
        fixture.service.refresh()
        await eventually { fixture.service.suggestions == ["world"] }
        #expect(fixture.service.accept(try #require(fixture.service.choice(for: "world"))))
        #expect(fixture.insertions == ["llo ", ",", " world "])
        #expect(fixture.deletions == [0, 2, 0])
    }

    @Test(arguments: ["hello  ,", "hello world", "hello (", "hello -", "hello /", "Hello ,"])
    func otherInputPreservesSpacingAndEndsTracking(_ text: String) async throws {
        let fixture = try await acceptedPrediction()
        defer { fixture.service.stop() }
        fixture.source.context = predictionContext(text)
        fixture.service.refresh()
        fixture.source.context = predictionContext("hello ,")
        fixture.service.refresh()
        #expect(fixture.insertions == ["llo "])
    }

    @Test func punctuationAtLineEndReplacesThePredictionSpace() async throws {
        let fixture = PredictionFixture()
        fixture.model.reason = "Unavailable"
        fixture.native.immediateWords = ["hello"]
        fixture.source.context = predictionContext("hel\nnext", cursor: 3)
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.service.suggestions == ["hello"] }
        #expect(fixture.service.accept(word: "hello"))
        fixture.source.context = predictionContext("hello \nnext", cursor: 6)
        fixture.service.refresh()
        fixture.source.context = predictionContext("hello .\nnext", cursor: 7)
        fixture.service.refresh()
        #expect(fixture.insertions == ["lo ", "."])
        #expect(fixture.deletions == [0, 2])
    }

    @Test func punctuationTypedAwayFromTheWordIsNotCorrected() async throws {
        let fixture = PredictionFixture()
        fixture.model.reason = "Unavailable"
        fixture.native.immediateWords = ["hello"]
        fixture.source.context = predictionContext("hel\nnext", cursor: 3)
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.service.suggestions == ["hello"] }
        #expect(fixture.service.accept(word: "hello"))
        fixture.source.context = predictionContext("hello \nnext.", cursor: 12)
        fixture.service.refresh()
        #expect(fixture.insertions == ["lo "])
    }

    @Test func manuallyTypedSpaceIsNotCorrected() {
        let fixture = PredictionFixture()
        fixture.model.reason = "Unavailable"
        fixture.native.immediateWords = []
        fixture.source.context = predictionContext("hello ")
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        fixture.source.context = predictionContext("hello ,")
        fixture.service.refresh()
        #expect(fixture.insertions.isEmpty)
    }

    @Test func waitsForPredictionDeliveryThenCorrectsPunctuation() async throws {
        let fixture = try await acceptedPrediction()
        defer { fixture.service.stop() }
        fixture.service.refresh()
        fixture.source.context = predictionContext("hello ")
        fixture.service.refresh()
        fixture.source.context = predictionContext("hello ,")
        fixture.service.refresh()
        #expect(fixture.insertions == ["llo ", ","])
    }

    @Test func deletingAcceptedWordEndsSpaceTracking() async throws {
        let fixture = try await acceptedPrediction()
        defer { fixture.service.stop() }
        fixture.source.context = predictionContext("hello ")
        fixture.service.refresh()
        fixture.source.context = predictionContext("he")
        fixture.service.refresh()
        fixture.source.context = predictionContext("hello ,")
        fixture.service.refresh()
        #expect(fixture.insertions == ["llo "])
    }

    enum ContextChange: CaseIterable {
        case focus, cursor, selection, missing, shortcut, stop, language
    }

    @Test(arguments: ContextChange.allCases)
    func changedContextEndsSpaceTracking(_ change: ContextChange) async throws {
        let fixture = try await acceptedPrediction()
        defer { fixture.service.stop() }
        switch change {
        case .focus:
            fixture.source.context = predictionContext("hello ,", elementID: 2)
        case .cursor:
            fixture.source.context = predictionContext("hello ,", cursor: 6)
        case .selection:
            fixture.source.context = predictionContext("hello ,", selectionLength: 1)
        case .missing:
            fixture.source.context = nil
        case .shortcut:
            fixture.shortcuts = true
        case .stop:
            fixture.service.stop()
        case .language:
            fixture.language = "de"
        }
        fixture.service.refresh()
        fixture.shortcuts = false
        fixture.language = "en"
        fixture.source.context = predictionContext("hello ,")
        fixture.service.start(polling: false)
        fixture.service.refresh()
        #expect(fixture.insertions == ["llo "])
    }

    @Test func failedPredictionDoesNotArmSpaceCorrection() async throws {
        let fixture = try await acceptedPrediction(failsInsertion: true)
        defer { fixture.service.stop() }
        fixture.failsInsertion = false
        fixture.source.context = predictionContext("hello ,")
        fixture.service.refresh()
        #expect(fixture.insertions.isEmpty)
    }

    // MARK: - Spacing Fixture
    private func acceptedPrediction(failsInsertion: Bool = false) async throws -> PredictionFixture
    {
        let fixture = PredictionFixture()
        fixture.model.reason = "Unavailable"
        fixture.native.immediateWords = ["hello"]
        fixture.failsInsertion = failsInsertion
        fixture.service.start(polling: false)
        await eventually { fixture.service.suggestions == ["hello"] }
        let choice = try #require(fixture.service.choice(for: "hello"))
        #expect(fixture.service.accept(choice) == !failsInsertion)
        return fixture
    }
}
