# Swipe typing models and decoder

Source: [anomalyco/hex](https://github.com/anomalyco/hex), by Christopher Langton.
Upstream revision: `9338afcd4d4718f51a66f5f0313cc95041f8d4dc`.
Repository license: MIT; the complete notice is in `LICENSE-hex.txt` and is bundled with the app.

## Code

`Tastko/Features/SwipeTyping` ports these upstream files at the revision above:

- `ios/HEXShared/FullKeyboard/SwipeDecoder.swift`: the swipe decoder, unchanged in behaviour.
- `ios/HEXShared/FullKeyboard/TypingDecoder.swift`: the `TypingDecoderModel` reader and
  `NeverSuggest`.
- `ios/HEXShared/Spelling/HexWordList.swift`, `ios/HEXShared/FullKeyboard/GermanCapitals.swift`
  and `ios/HEXShared/FullKeyboard/OffensiveWords.swift`.

They were reformatted, marked `nonisolated` for Tastko's `MainActor` default isolation, and
trimmed to what swipe typing reads.

## Data

Copied byte for byte from the revision above. SHA-256 hashes match upstream
`android/app/src/main/assets/typing/SHA256SUMS`.

| File | Upstream path | SHA-256 |
| --- | --- | --- |
| `en.hextm` | `ios/HEXKeyboard/TypingModel/en.hextm` | `c23e9c546d620fa6d8d395b9dae72cb7825b39050fc1782b548b829729a6df30` |
| `de.hextm` | `ios/HEXKeyboard/TypingModel/de.hextm` | `7854e9a3c6788f9ff568a476d84c9f9a0f7b6b2c794df4375424252860998355` |
| `de.capitals` | `ios/HEXKeyboard/TypingModel/de.capitals` | `7b1b24ff18868fb32e049502806ef3737ad91bde685239a4cc28ae38185f3ef9` |

`never-suggest.tsv` keeps upstream `ios/HEXShared/FullKeyboard/never-suggest.tsv`'s shared
(`*`), English (`en`) and German (`de`) rows unchanged; its header comment was shortened.

### Google Books Ngram data

The word and word-pair frequencies in `en.hextm` and `de.hextm`, and the capitalisation shares
in `de.capitals`, come from the Google Books Ngram Viewer data, version 3 (2020), by Google,
licensed under [Creative Commons Attribution 3.0](https://creativecommons.org/licenses/by/3.0/).
Counts are summed over 1980–2019. Hex converted them to its HXTM v3 format. German keeps the
corpus's own spellings; English keeps only words SCOWL lists, below.

### SCOWL

English words are checked against SCOWL (Spell Checker Oriented Word Lists) and VarCon by
Kevin Atkinson, sizes up to 70 (<http://wordlist.aspell.net/>).

Copyright 2000-2018 by Kevin Atkinson

Permission to use, copy, modify, distribute and sell these word lists, the associated
scripts, the output created from the scripts, and its documentation for any purpose is
hereby granted without fee, provided that the above copyright notice appears in all copies
and that both that copyright notice and this permission notice appear in supporting
documentation. Kevin Atkinson makes no representations about the suitability of this array
for any purpose. It is provided "as is" without express or implied warranty.

SCOWL's inflections come from WordNet 1.6, Copyright 1997 by Princeton University. All
rights reserved. THIS SOFTWARE AND DATABASE IS PROVIDED "AS IS" AND PRINCETON UNIVERSITY
MAKES NO REPRESENTATIONS OR WARRANTIES, EXPRESS OR IMPLIED. BY WAY OF EXAMPLE, BUT NOT
LIMITATION, PRINCETON UNIVERSITY MAKES NO REPRESENTATIONS OR WARRANTIES OF MERCHANTABILITY
OR FITNESS FOR ANY PARTICULAR PURPOSE OR THAT THE USE OF THE LICENSED SOFTWARE, DATABASE OR
DOCUMENTATION WILL NOT INFRINGE ANY THIRD PARTY PATENTS, COPYRIGHTS, TRADEMARKS OR OTHER
RIGHTS. The name of Princeton University or Princeton may not be used in advertising or
publicity pertaining to distribution of the software and/or database.

Its other sources (12Dicts, Moby Words II, and Brian Kelk's UK English Wordlist) are in the
public domain.

### LDNOOBW

`never-suggest.tsv` comes from the List of Dirty, Naughty, Obscene, and Otherwise Bad Words
(LDNOOBW), © 2012–2020 Shutterstock, Inc., and contributors, revision `5faf2ba`
(<https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words>), licensed
under [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/).
Hex lowercased and classified the entries, omitted ordinary, medical and search-only terms, and
added common slurs, inflections and spelling variants. Swipe typing never offers a listed word.
