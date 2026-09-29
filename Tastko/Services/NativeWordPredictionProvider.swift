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
    /// The checker language that completes words, keyed by the requested language.
    private var spellLanguages: [String: String] = [:]

    // MARK: - Language Warm-Up
    func prewarm(language requested: String) {
        let language = spellLanguage(for: requested)
        guard language != self.language, selectLanguage(language),
            let input = PredictionInput(
                text: "",
                range: AccessibilityTextRange(location: 0, length: 0),
                language: requested
            )
        else { return }
        // A throwaway request starts loading the predictor before the first real one.
        Task { _ = await candidates(for: input, language: language) }
    }

    // MARK: - Native Candidates
    func predictions(for input: PredictionInput) async -> [String] {
        guard !Task.isCancelled else { return [] }
        let language = spellLanguage(for: input.language)
        guard selectLanguage(language) else {
            return dictionaryCompletions(for: input, language: language)
        }
        var words = await candidates(for: input, language: language)
        if words.isEmpty, let languageSwitched,
            languageSwitched.duration(to: .now) < .seconds(1)
        {
            try? await Task.sleep(for: Self.languageSwitchDelay)
            guard !Task.isCancelled else { return [] }
            words = await candidates(for: input, language: language)
        }
        guard !Task.isCancelled else { return [] }
        let validated = input.validated(words)
        guard validated.count < PredictionInput.maximumSuggestions else { return validated }
        return input.validated(validated + dictionaryCompletions(for: input, language: language))
    }

    private func candidates(for input: PredictionInput, language: String) async -> [String] {
        let checker = NSSpellChecker.shared
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }
        return await withCheckedContinuation { continuation in
            checker.requestCandidates(
                forSelectedRange: NSRange(location: input.context.utf16.count, length: 0),
                in: input.context,
                types: NSTextCheckingResult.CheckingType([.replacement, .correction]).rawValue,
                options: [
                    .orthography: NSOrthography.defaultOrthography(forLanguage: language),
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

    // MARK: - Spell Language Resolution
    /// Resolves the checker language once per requested language. Some variants
    /// answer only with corrections: bundled apps can get no completions for `en`
    /// while `en_GB` works, so a variant must prove it completes a word first.
    private func spellLanguage(for requested: String) -> String {
        if let resolved = spellLanguages[requested] { return resolved }
        let checker = NSSpellChecker.shared
        let resolved = Self.spellLanguage(
            for: requested,
            preferred: checker.userPreferredLanguages,
            available: checker.availableLanguages
        ) { language, probe in
            !(checker.completions(
                forPartialWordRange: NSRange(location: 0, length: probe.utf16.count),
                in: probe,
                language: language,
                inSpellDocumentWithTag: 0
            ) ?? []).isEmpty
        }
        spellLanguages[requested] = resolved
        return resolved
    }

    /// Picks the first variant of `requested` that completes a probe word: the request
    /// itself, then the person's spelling preferences, then other installed variants.
    static func spellLanguage(
        for requested: String,
        preferred: [String],
        available: [String],
        completes: (_ language: String, _ probe: String) -> Bool
    ) -> String {
        let base = Locale(identifier: requested).language.languageCode
        // The language's own name is a word every dictionary for it can complete.
        guard let base,
            let name = Locale(identifier: requested).localizedString(
                forLanguageCode: base.identifier
            )
        else { return requested }
        let probe = String(name.lowercased().prefix(2))
        var variants = [requested]
        for language in preferred + available
        where Locale(identifier: language).language.languageCode == base
            && !variants.contains(language)
        {
            variants.append(language)
        }
        return variants.first { completes($0, probe) } ?? requested
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
    private func dictionaryCompletions(for input: PredictionInput, language: String) -> [String] {
        guard !input.prefix.isEmpty else { return [] }
        return NSSpellChecker.shared.completions(
            forPartialWordRange: NSRange(
                location: input.context.utf16.count - input.prefix.utf16.count,
                length: input.prefix.utf16.count
            ),
            in: input.context,
            language: language,
            inSpellDocumentWithTag: 0
        ) ?? []
    }
}
