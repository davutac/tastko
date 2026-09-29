import Testing

@testable import Tastko

// MARK: - NativeSpellLanguageTests
@MainActor
struct NativeSpellLanguageTests {
    private let available = ["de", "en_GB", "en_AU", "en", "fr"]

    // MARK: - Resolution
    @Test func keepsTheRequestedLanguageWhenItCompletesWords() {
        let resolved = NativeWordPredictionProvider.spellLanguage(
            for: "en",
            preferred: ["de", "en_GB"],
            available: available
        ) { _, _ in true }
        #expect(resolved == "en")
    }

    @Test func fallsBackToThePreferredVariantThatCompletesWords() {
        // Captured in a bundled app: `en` returned no completions while `en_GB` did.
        var probes: [String] = []
        let resolved = NativeWordPredictionProvider.spellLanguage(
            for: "en",
            preferred: ["de", "en_AU", "en_GB"],
            available: available
        ) { language, probe in
            probes.append(probe)
            return language == "en_GB"
        }
        #expect(resolved == "en_GB")
        #expect(Set(probes) == ["en"])
    }

    @Test func triesOtherInstalledVariantsAndNeverOtherLanguages() {
        var tried: [String] = []
        let resolved = NativeWordPredictionProvider.spellLanguage(
            for: "en",
            preferred: ["de"],
            available: available
        ) { language, _ in
            tried.append(language)
            return false
        }
        #expect(resolved == "en")
        #expect(tried == ["en", "en_GB", "en_AU"])
    }

    @Test func probesWithTheLanguageName() {
        var probe = ""
        _ = NativeWordPredictionProvider.spellLanguage(
            for: "de",
            preferred: [],
            available: available
        ) { _, word in
            probe = word
            return true
        }
        #expect(probe == "de")
    }
}
