import AppKit

// MARK: - NativeWordPredicting
@MainActor
protocol NativeWordPredicting {
    func prewarm(language: String)
    func predictions(for input: PredictionInput) async -> [String]
}

// MARK: - NativeWordPredictionProvider
@MainActor
final class NativeWordPredictionProvider: NativeWordPredicting {
    /// Candidates stay empty for a moment after the checker switches language.
    private static let languageSwitchDelay: Duration = .milliseconds(300)
    private var language: String?
    private var languageSwitched: ContinuousClock.Instant?

    // MARK: - Language Warm-Up
    func prewarm(language: String) {
        guard language != self.language, selectLanguage(language),
            let input = PredictionInput(
                text: "",
                range: AccessibilityTextRange(location: 0, length: 0),
                language: language
            )
        else { return }
        // A throwaway request starts loading the predictor before the first real one.
        Task { _ = await candidates(for: input) }
    }

    // MARK: - Native Candidates
    func predictions(for input: PredictionInput) async -> [String] {
        guard !Task.isCancelled else { return [] }
        guard selectLanguage(input.language) else {
            return dictionaryCompletions(for: input)
        }
        var words = await candidates(for: input)
        if words.isEmpty, let languageSwitched,
            languageSwitched.duration(to: .now) < .seconds(1)
        {
            try? await Task.sleep(for: Self.languageSwitchDelay)
            guard !Task.isCancelled else { return [] }
            words = await candidates(for: input)
        }
        guard !Task.isCancelled else { return [] }
        let validated = input.validated(words)
        guard validated.count < PredictionInput.maximumSuggestions else { return validated }
        return input.validated(validated + dictionaryCompletions(for: input))
    }

    private func candidates(for input: PredictionInput) async -> [String] {
        let checker = NSSpellChecker.shared
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }
        return await withCheckedContinuation { continuation in
            checker.requestCandidates(
                forSelectedRange: NSRange(location: input.context.utf16.count, length: 0),
                in: input.context,
                types: NSTextCheckingResult.CheckingType([.replacement, .correction]).rawValue,
                options: [
                    .orthography: NSOrthography.defaultOrthography(forLanguage: input.language),
                    .generateInlinePredictionsKey: true,
                ],
                inSpellDocumentWithTag: tag
            ) { _, candidates in
                // AppKit may call back off the main actor. Only immutable words leave
                // this callback; the service rejects cancelled and stale requests.
                continuation.resume(
                    returning: candidates.compactMap { candidate in
                        guard let replacement = candidate.replacementString else { return nil }
                        return input.nativeCandidate(
                            replacement: replacement,
                            range: candidate.range
                        )
                    }
                )
            }
        }
    }

    // MARK: - Language Selection
    /// Selects the checker language and records when it last changed.
    private func selectLanguage(_ language: String) -> Bool {
        let checker = NSSpellChecker.shared
        // Orthography alone does not override candidate language detection for short
        // prefixes. This checker belongs to Tastko, not the external target app.
        checker.automaticallyIdentifiesLanguages = false
        guard checker.setLanguage(language) else { return false }
        if language != self.language {
            self.language = language
            languageSwitched = .now
        }
        return true
    }

    // MARK: - Dictionary Fallback
    private func dictionaryCompletions(for input: PredictionInput) -> [String] {
        guard !input.prefix.isEmpty else { return [] }
        return NSSpellChecker.shared.completions(
            forPartialWordRange: NSRange(
                location: input.context.utf16.count - input.prefix.utf16.count,
                length: input.prefix.utf16.count
            ),
            in: input.context,
            language: input.language,
            inSpellDocumentWithTag: 0
        ) ?? []
    }
}
