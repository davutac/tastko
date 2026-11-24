// Ported from Hex (github.com/anomalyco/hex, revision 9338afc,
// ios/HEXShared/FullKeyboard/OffensiveWords.swift). MIT license: see
// Resources/TypingModel/LICENSE-hex.txt and SOURCE-hex.md.

import Foundation

// MARK: - OffensiveWords
/// Words swipe typing never reads (`Resources/TypingModel/never-suggest.tsv`: LDNOOBW, curated by
/// Hex). A swipe inserts its best reading without a click, so a listed word must never be one.
/// They stay in the word models, so a word typed with taps is unaffected.
nonisolated struct OffensiveWords: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case slur
        case swear
    }

    /// Lowercased spellings and two-word expressions (one space between), accents kept.
    private(set) var entries: [String: Kind] = [:]

    // MARK: - Loading
    init(entries: [String: Kind] = [:]) {
        self.entries = entries
    }

    /// Reads `layout<TAB>slur|swear<TAB>spelling` lines for `language`, and the `*` lines every
    /// layout shares; `#` starts a comment.
    init(tsv: String, language: String) {
        var entries: [String: Kind] = [:]
        for line in tsv.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3, fields[0] == "*" || fields[0] == language[...] else {
                continue
            }
            let kind: Kind
            switch fields[1] {
            case "slur": kind = .slur
            case "swear": kind = .swear
            default: continue
            }
            let spelling = fields[2].lowercased().split(separator: " ").joined(separator: " ")
            guard !spelling.isEmpty else { continue }
            if entries[spelling] != .slur { entries[spelling] = kind }
        }
        self.init(entries: entries)
    }

    // MARK: - Blocked Words
    /// The spellings and two-word expressions to block: slurs always, swear words unless
    /// `allowSwearing`.
    func blocked(allowSwearing: Bool) -> [String] {
        entries.compactMap { word, kind in kind == .slur || !allowSwearing ? word : nil }
    }
}
