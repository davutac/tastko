import CoreGraphics
import Foundation

// MARK: - SwipeStroke
/// A pointer's positions during a press, in panel coordinates, and when each came: the decoder
/// reads where the pointer paused from the times.
nonisolated struct SwipeStroke: Equatable, Sendable {
    private(set) var points: [CGPoint] = []
    private(set) var times: [TimeInterval] = []

    init() {}

    init(_ point: CGPoint, at time: TimeInterval) {
        add(point, at: time)
    }

    mutating func add(_ point: CGPoint, at time: TimeInterval) {
        points.append(point)
        times.append(time)
    }
}

// MARK: - SwipeVocabulary
/// A language's swipe typing data: its decoder over the bundled word model, never reading a
/// listed offensive word, and how its words are written.
nonisolated struct SwipeVocabulary: Sendable {
    /// Languages with a bundled model (`Resources/TypingModel/<code>.hextm`).
    static let languages: Set<String> = ["en", "de"]

    let language: String
    private(set) var decoder: SwipeDecoder
    private let capitals: GermanCapitals?

    // MARK: - Loading
    /// The bundled vocabulary for a language code ("en", "de-DE"), or nil when Tastko has no
    /// model for it.
    init?(languageCode: String, bundle: Bundle = .main) {
        guard let language = Self.language(for: languageCode),
            let url = bundle.url(forResource: language, withExtension: "hextm"),
            let model = TypingDecoderModel(url: url), model.language == language
        else { return nil }
        let tsv =
            bundle.url(forResource: "never-suggest", withExtension: "tsv")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        self.init(
            model: model,
            neverSuggest: OffensiveWords(tsv: tsv, language: language)
                .blocked(allowSwearing: false),
            capitals: bundle.url(forResource: language, withExtension: "capitals")
                .flatMap { GermanCapitals(url: $0) }
        )
    }

    init(model: TypingDecoderModel, neverSuggest: [String] = [], capitals: GermanCapitals? = nil) {
        language = model.language
        decoder = SwipeDecoder(model: model)
        decoder.neverSuggest = SwipeDecoder.NeverSuggest(neverSuggest, model: model)
        self.capitals = capitals
    }

    /// The model's language for a language code or identifier ("de-DE" is "de").
    static func language(for code: String) -> String? {
        let language = code.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first.map(String.init)
        return language.flatMap { languages.contains($0) ? $0 : nil }
    }

    /// The decoder's weights and thresholds.
    var parameters: SwipeDecoder.Parameters {
        get { decoder.parameters }
        set { decoder.parameters = newValue }
    }

    /// The letters the model spells words with.
    var alphabet: Set<Character> {
        Set(decoder.model.codes.keys.filter(\.isLetter))
    }

    // MARK: - Reading
    /// The likeliest words for `stroke` across `keys`, best first, as the model spells them
    /// (lowercase). `previous` is the word before, which weighs them. The pointer's
    /// back-and-forth janks are taken out first (`SwipePathFilter`).
    func readings(
        _ stroke: SwipeStroke,
        keys: SwipeDecoder.Keys,
        previous: String?,
        limit: Int = 8
    ) -> [String] {
        let path = SwipePathFilter.withoutJank(
            stroke.points,
            times: stroke.times,
            pitch: Double(keys.pitch.width)
        )
        return decoder.decode(
            path.points,
            times: path.times,
            keys: keys,
            previous: previous,
            limit: limit
        )
        .map(\.text)
    }

    // MARK: - Spelling
    /// How the language writes a word the model spells lowercase: English's "I" and its
    /// contractions, and a German noun's capital.
    func spelling(of word: String, after previous: String?) -> String {
        switch language {
        case "en" where word == "i" || word.hasPrefix("i'"):
            return "I" + word.dropFirst()
        case "de" where capitals?.capitalises(word, after: previous) == true:
            return word.prefix(1).uppercased() + word.dropFirst()
        default:
            return word
        }
    }

    /// The word right before the cursor in `text` that a swiped word follows, lowercase; nil
    /// at a sentence's or field's start, or after punctuation.
    static func previousWord(before text: String) -> String? {
        let trimmed = text.reversed().drop(while: { $0 == " " || $0 == "\t" })
        let word = String(
            trimmed.prefix(while: { $0.isLetter || $0 == "'" || $0 == "’" }).reversed()
        )
        .replacingOccurrences(of: "’", with: "'")
        .lowercased()
        return word.isEmpty ? nil : word
    }
}
