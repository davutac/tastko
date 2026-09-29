import ApplicationServices
import Foundation
import Testing

@testable import Tastko

// MARK: - TextPredictionServiceTests
@MainActor
struct TextPredictionServiceTests {
    // MARK: - Empty Context
    @Test func emptyFieldSuggestsStarterWords() async throws {
        let fixture = PredictionFixture()
        fixture.model.reason = "Unavailable"
        fixture.native.immediateWords = ["I", "The"]
        fixture.source.context = predictionContext("")
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.service.suggestions == ["I", "The"] }
        #expect(fixture.service.hasTextContext)
        #expect(fixture.service.accept(word: "The"))
        #expect(fixture.insertions == ["The "])
    }

    @Test func emptiedFieldDropsWordsForDeletedText() async {
        let fixture = PredictionFixture()
        fixture.model.reason = "Unavailable"
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.native.requests.count == 1 }
        fixture.native.finish(0, words: ["hello"])
        await eventually { fixture.service.suggestions == ["hello"] }
        fixture.source.context = predictionContext("")
        fixture.service.keyboardDidChange()
        fixture.service.refresh()
        #expect(fixture.service.suggestions.isEmpty)
        await eventually { fixture.native.requests.count == 2 }
        fixture.native.finish(1, words: ["I"])
        await eventually { fixture.service.suggestions == ["I"] }
    }

    @Test func prewarmsNativeLanguageOnStartAndLanguageChange() {
        let fixture = PredictionFixture()
        fixture.model.reason = "Unavailable"
        fixture.native.immediateWords = []
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        fixture.language = "de"
        fixture.service.refresh()
        #expect(fixture.native.prewarmedLanguages == ["en", "de"])
    }

    @Test(arguments: [true, false])
    func deletingContextClearsPreservedWordsAndRejectsLateResults(_ readable: Bool) async throws {
        let fixture = PredictionFixture()
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.native.requests.count == 1 && fixture.model.requests.count == 1 }
        fixture.native.finish(0, words: ["hello"])
        await eventually { fixture.service.suggestions == ["hello"] }
        let choice = try #require(fixture.service.choice(for: "hello"))
        fixture.source.context = readable ? predictionContext("") : nil
        #expect(fixture.service.choice(for: "hello") == nil)
        fixture.service.keyboardDidChange()
        fixture.service.refresh()
        #expect(fixture.service.suggestions.isEmpty)
        #expect(fixture.service.typedPrefix.isEmpty)
        // An empty field is still text context and asks for starter words.
        #expect(fixture.service.hasTextContext == readable)
        fixture.model.updates[0](["help"])
        fixture.model.finish(0, words: ["help"])
        if readable {
            // The emptied field asks for starters once the stale request ends.
            await eventually { fixture.model.requests.count == 2 }
            fixture.model.finish(1, words: [])
        }
        await eventually { fixture.model.active == 0 }
        #expect(fixture.service.suggestions.isEmpty)
        #expect(!fixture.service.accept(choice))
        fixture.native.finishAll()
    }

    // MARK: - Streaming
    @Test func publishesCompletedStreamedWordsAndRejectsStaleStreamUpdates() async {
        let fixture = PredictionFixture()
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.model.requests.count == 1 && fixture.native.requests.count == 1 }
        fixture.native.finish(0, words: ["hello"])
        fixture.model.updates[0](["help"])
        #expect(fixture.service.suggestions.first == "help")
        fixture.source.context = predictionContext("wor")
        fixture.service.refresh()
        fixture.model.updates[0](["help", "hello"])
        #expect(fixture.service.suggestions == ["help"])
        #expect(fixture.service.choice(for: "help") != nil)
        fixture.model.finish(0, words: ["hello"])
        await eventually { fixture.model.requests.count == 2 && fixture.native.requests.count == 2 }
        fixture.native.finish(1, words: [])
        fixture.model.finish(1, words: ["world"])
        await eventually { fixture.service.suggestions == ["world"] }
    }

    // MARK: - Stable Presentation
    @Test(arguments: ["hel", "hello", "helloo", "hex", "We say wor", "hello "])
    func acceptsVisibleSuggestionAfterPrefixChanges(_ text: String) async throws {
        let fixture = PredictionFixture()
        fixture.model.reason = "Unavailable"
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.native.requests.count == 1 }
        fixture.native.finish(0, words: ["hello"])
        await eventually { fixture.service.suggestions == ["hello"] }

        fixture.source.context = predictionContext(text)
        fixture.service.keyboardDidChange()
        fixture.service.refresh()
        #expect(fixture.service.suggestions == ["hello"])
        let choice = try #require(fixture.service.choice(for: "hello"))
        #expect(choice.context.input.context == text)
        #expect(fixture.service.accept(choice))
        #expect(fixture.insertions.count == 1)
        let prefix = choice.context.input.prefix
        let expected = String(text.dropLast(prefix.count)) + "hello "
        let actual = String(text.dropLast(fixture.deletions[0])) + fixture.insertions[0]
        #expect(actual == expected)
    }

    // MARK: - Target Safety
    @Test func visibleSuggestionCannotMoveToAnotherTextField() async {
        let fixture = PredictionFixture()
        fixture.model.reason = "Unavailable"
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.native.requests.count == 1 }
        fixture.native.finish(0, words: ["hello"])
        await eventually { fixture.service.suggestions == ["hello"] }
        fixture.source.context = predictionContext("hex", elementID: 2)
        #expect(fixture.service.choice(for: "hello") == nil)
        #expect(fixture.insertions.isEmpty)
    }

    // MARK: - Refresh
    @Test func keyPressKeepsSuggestionsClickableWhileRefreshing() async throws {
        let fixture = PredictionFixture()
        fixture.model.reason = "Unavailable"
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.native.requests.count == 1 }
        fixture.native.finish(0, words: ["hello"])
        await eventually { fixture.service.suggestions == ["hello"] }

        fixture.service.keyboardDidChange()
        #expect(fixture.service.hasTextContext)
        #expect(fixture.service.suggestions == ["hello"])
        #expect(fixture.service.choice(for: "hello") != nil)

        fixture.source.context = predictionContext("hel")
        fixture.service.refresh()
        #expect(fixture.service.hasTextContext)
        #expect(fixture.service.typedPrefix == "hel")
        #expect(fixture.service.suggestions == ["hello"])
        let choice = try #require(fixture.service.choice(for: "hello"))
        #expect(choice.context.input.prefix == "hel")
        #expect(fixture.service.accept(choice))
        #expect(fixture.insertions == ["lo "])
        fixture.service.refresh()
        await eventually { fixture.native.requests.count == 2 }
        fixture.native.finish(1, words: ["hello", "help"])
        await eventually { fixture.service.suggestions == ["hello", "help"] }
        #expect(fixture.service.choice(for: "hello")?.context.input.prefix == "hel")
    }

    // MARK: - Responses
    @Test func nativeCompletionsArriveBeforeModelAndMergeWithoutDuplicates() async throws {
        let fixture = PredictionFixture()
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.native.requests.count == 1 && fixture.model.requests.count == 1 }
        fixture.native.finish(0, words: ["hello", "help", "helmet"])
        await eventually { fixture.service.suggestions.count == 3 }
        #expect(fixture.service.suggestions == ["hello", "help", "helmet"])
        fixture.model.finish(0, words: ["help", "hero", "wrong phrase"])
        await eventually { fixture.model.resetCount == 1 }
        #expect(fixture.service.suggestions == ["hello", "help", "helmet", "hero"])
    }

    @Test func nativeNextWordsWorkWithoutAI() async throws {
        let fixture = PredictionFixture()
        fixture.model.reason = "Unavailable"
        fixture.source.context = predictionContext("We can meet ")
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.native.requests.count == 1 }
        fixture.native.finish(0, words: ["at", "up", "tomorrow"])
        await eventually { fixture.service.suggestions == ["at", "up", "tomorrow"] }
        #expect(fixture.model.requests.isEmpty)
        #expect(fixture.service.accept(try #require(fixture.service.choice(for: "tomorrow"))))
        #expect(fixture.insertions == ["tomorrow "])
    }

    @Test func aiFillsGapsWithoutReorderingNativeCandidates() async {
        let fixture = PredictionFixture()
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.native.requests.count == 1 && fixture.model.requests.count == 1 }
        fixture.native.finish(0, words: ["hello"])
        await eventually { fixture.service.suggestions == ["hello"] }
        fixture.model.finish(0, words: ["help", "hello", "helmet"])
        await eventually { fixture.model.resetCount == 1 }
        #expect(fixture.service.suggestions == ["hello", "help", "helmet"])
    }

    @Test func aiWordsFollowTopNativeWordsWhenNativeFillsTheStrip() async throws {
        let fixture = PredictionFixture(debounce: .milliseconds(20))
        let words = [
            "hello", "help", "helmet", "hero", "helping", "helpful", "helicopter", "herald",
            "heaven",
        ]
        fixture.native.immediateWords = words
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.service.suggestions.count == PredictionInput.maximumSuggestions }
        #expect(fixture.service.suggestions == Array(words.prefix(8)))
        // Real native candidates return about twenty words, so AI must not wait for gaps.
        await eventually { fixture.model.requests.count == 1 }
        fixture.model.finish(0, words: ["heat", "help", "heard"])
        await eventually { fixture.model.resetCount == 1 }
        #expect(
            fixture.service.suggestions == [
                "hello", "help", "helmet", "heat", "heard", "hero", "helping", "helpful",
            ]
        )
    }

    @Test func staleResponsesNeverPublishAndModelRequestsNeverOverlap() async throws {
        let fixture = PredictionFixture()
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.model.requests.count == 1 && fixture.native.requests.count == 1 }
        fixture.source.context = predictionContext("wor")
        fixture.service.refresh()
        await eventually { fixture.native.requests.count == 2 }
        fixture.native.finish(0, words: ["hello"])
        fixture.model.finish(0, words: ["hello"])
        await eventually { fixture.model.requests.count == 2 }
        #expect(fixture.service.suggestions.isEmpty)
        fixture.native.finish(1, words: ["world"])
        fixture.model.finish(1, words: ["words"])
        await eventually { fixture.service.suggestions == ["world", "words"] }
        #expect(fixture.model.maximumActive == 1)
    }

    @Test func debouncesRapidEditsAndHandlesDeletionAndLanguageChanges() async {
        let fixture = PredictionFixture(debounce: .milliseconds(20))
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        for text in ["hel", "hell", "hel", "he"] {
            fixture.source.context = predictionContext(text)
            fixture.service.refresh()
        }
        fixture.language = "de"
        fixture.service.refresh()
        await eventually { fixture.model.requests.count == 1 }
        #expect(fixture.model.inputs.first?.prefix == "he")
        #expect(fixture.model.inputs.first?.language == "de")
        fixture.native.finishAll()
        fixture.model.finish(0, words: [])
    }

    @Test func validatesChoiceAtAcceptance() async throws {
        let fixture = PredictionFixture()
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.native.requests.count == 1 && fixture.model.requests.count == 1 }
        fixture.native.finish(0, words: ["hello"])
        await eventually { !fixture.service.suggestions.isEmpty }
        let choice = try #require(fixture.service.choice(for: "hello"))
        fixture.model.finish(0, words: ["help"])
        await eventually { fixture.model.resetCount == 1 }
        #expect(fixture.service.suggestions == ["hello", "help"])
        #expect(fixture.service.accept(choice))
        #expect(fixture.insertions == ["llo "])
        #expect(fixture.deliveredPID == choice.context.target.processIdentifier)
    }

    @Test func rejectsChangedFieldTextAndCursorBeforePosting() async throws {
        for changed in [
            predictionContext("he", elementID: 2), predictionContext("hel"),
            predictionContext("he "),
        ] {
            let fixture = PredictionFixture()
            fixture.model.reason = "Unavailable"
            fixture.service.start(polling: false)
            await eventually { fixture.native.requests.count == 1 }
            fixture.native.finish(0, words: ["hello"])
            await eventually { !fixture.service.suggestions.isEmpty }
            let choice = try #require(fixture.service.choice(for: "hello"))
            fixture.source.context = changed
            #expect(!fixture.service.accept(choice))
            #expect(fixture.insertions.isEmpty)
            #expect(fixture.service.suggestions.isEmpty)
            fixture.service.stop()
        }
    }

    @Test func missingSecureOrSelectedContextAndShortcutsClearSuggestions() async {
        let fixture = PredictionFixture()
        fixture.model.reason = "Unavailable"
        fixture.service.start(polling: false)
        defer { fixture.service.stop() }
        await eventually { fixture.native.requests.count == 1 }
        fixture.native.finish(0, words: ["hello"])
        await eventually { !fixture.service.suggestions.isEmpty }
        fixture.shortcuts = true
        fixture.service.refresh()
        #expect(fixture.service.suggestions.isEmpty)
        fixture.shortcuts = false
        fixture.source.context = nil
        fixture.service.refresh()
        #expect(fixture.service.suggestions.isEmpty)
        #expect(fixture.model.requests.isEmpty)
    }

    @Test func modelFailurePreservesNativeAndStoppingRejectsLateResults() async {
        let fixture = PredictionFixture()
        fixture.service.start(polling: false)
        await eventually { fixture.native.requests.count == 1 && fixture.model.requests.count == 1 }
        fixture.native.finish(0, words: ["hello"])
        fixture.model.fail(0)
        await eventually { fixture.model.resetCount == 1 && !fixture.service.suggestions.isEmpty }
        #expect(fixture.service.suggestions == ["hello"])
        fixture.source.context = predictionContext("wor")
        fixture.service.refresh()
        await eventually { fixture.native.requests.count == 2 && fixture.model.requests.count == 2 }
        fixture.service.stop()
        fixture.native.finish(1, words: ["world"])
        fixture.model.finish(1, words: ["world"])
        await eventually { fixture.model.resetCount == 2 }
        #expect(fixture.service.suggestions.isEmpty)
        #expect(!fixture.service.isRunning)
        #expect(!fixture.source.observing)
    }

    @Test func disabledSettingStopsObservationAndPreventsAcceptance() async throws {
        let fixture = PredictionFixture()
        fixture.model.reason = "Unavailable"
        fixture.service.start(polling: false)
        await eventually { fixture.native.requests.count == 1 }
        fixture.native.finish(0, words: ["hello"])
        await eventually { !fixture.service.suggestions.isEmpty }
        let choice = try #require(fixture.service.choice(for: "hello"))
        fixture.enabled = false
        #expect(!fixture.service.accept(choice))
        fixture.service.refresh()
        #expect(!fixture.service.isRunning)
        #expect(!fixture.source.observing)
    }
}
