// Ported from Hex (github.com/anomalyco/hex, revision 9338afc,
// ios/HEXShared/FullKeyboard/GermanCapitals.swift). MIT license: see
// Resources/TypingModel/LICENSE-hex.txt and SOURCE-hex.md.

import Foundation

// MARK: - GermanCapitals
/// German nouns' share of capitalised uses, read from `Resources/TypingModel/de.capitals` beside
/// the German typing model. One `word<TAB>percent` line per word (lowercase, sorted): the percent
/// is how often the word is written with a capital in the Google Books corpus the model was
/// counted from, so "haus" is 99 and "leben" (`Leben` the noun or `leben` the verb) is lower. A
/// word that is equally a common verb form or stem ("frage", "reise") is capped at 94, so it
/// takes a capital only after a determiner. German's model is lowercase throughout, so this list
/// is what knows a swiped word is a noun.
nonisolated struct GermanCapitals: Sendable {
    /// A word the books write with a capital this often is a noun wherever it stands.
    static let alwaysShare = 95
    /// From this share it is a noun after an article or determiner ("das leben").
    static let sometimesShare = 50

    /// The share for a lowercase word: from the mapped list, or the table tests give.
    private let share: @Sendable (String) -> UInt8?

    // MARK: - Loading
    init(percentages: [String: UInt8]) {
        share = { percentages[$0] }
    }

    /// The list memory-mapped and searched in place (`HexWordList`).
    init?(url: URL) {
        guard let list = HexWordList(url: url) else { return nil }
        share = { word in
            // The builder writes every word lowercase, from a lowercase-only model.
            guard let percent = list.value(of: word), (Self.sometimesShare...100).contains(percent)
            else { return nil }
            return UInt8(percent)
        }
    }

    // MARK: - Capitalisation
    /// The share of the word's corpus occurrences written with a capital (50–100), or nil when
    /// the list doesn't know the word.
    func percent(of word: String) -> UInt8? {
        share(word.lowercased())
    }

    /// Whether `word`, all lowercase, takes a capital: a noun written with one at least
    /// `alwaysShare` percent of the time anywhere, or `sometimesShare` percent of the time after
    /// an article or determiner. Nil when the list doesn't know the word.
    func capitalises(_ word: String, after previous: String?) -> Bool? {
        guard word.count >= 2, word == word.lowercased(),
            let share = percent(of: word), share >= Self.sometimesShare
        else { return nil }
        if share >= Self.alwaysShare { return true }
        return previous.map { Self.determiners.contains($0.lowercased()) } ?? false
    }

    /// Articles, determiners, their contractions and possessives, after which German writes the
    /// noun with a capital ("das haus", "im haus", "mein haus"). "ihr" is left out: as the
    /// pronoun "you" (plural) it comes before a verb far more often than as "her/their".
    static let determiners: Set<String> = [
        "der", "die", "das", "den", "dem", "des",
        "ein", "eine", "einen", "einem", "einer", "eines",
        "kein", "keine", "keinen", "keinem", "keiner", "keines",
        "mein", "meine", "meinen", "meinem", "meiner", "meines",
        "dein", "deine", "deinen", "deinem", "deiner", "deines",
        "sein", "seine", "seinen", "seinem", "seiner", "seines",
        "ihre", "ihren", "ihrem", "ihrer", "ihres",
        "unser", "unsere", "unseren", "unserem", "unserer", "unseres",
        "euer", "eure", "euren", "eurem", "eurer", "eures",
        "dies", "dieser", "diese", "dieses", "diesem", "diesen",
        "jeder", "jede", "jedes", "jedem", "jeden",
        "im", "in", "am", "zum", "zur", "vom", "beim", "ins", "ans",
    ]
}
