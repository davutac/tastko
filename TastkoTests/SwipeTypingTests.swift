import CoreGraphics
import Foundation
import Testing

@testable import Tastko

// MARK: - SwipeVocabularyTests
// Off the main actor: decoding in a Debug build is slow, and main-actor tests that wait on
// timers share that actor.
struct SwipeVocabularyTests {
    // MARK: - Decoding
    @Test(arguments: ["hello", "world", "keyboard", "typing", "quick", "please", "don't", "i'm"])
    func englishWordsDecodeOnAMacQWERTYGrid(word: String) throws {
        let vocabulary = try #require(SwipeTestVocabulary.english)
        let map = try #require(SwipeKeyMap(letterKeys: SwipeGrid.qwerty))
        let readings = vocabulary.readings(
            SwipeGrid.stroke(word, on: map),
            keys: map.keys,
            previous: nil
        )
        #expect(readings.first == word)
    }

    @Test(arguments: ["zeit", "über", "straße", "müssen", "schön"])
    func germanWordsDecodeOnQWERTZ(word: String) throws {
        let vocabulary = try #require(SwipeTestVocabulary.german)
        let map = try #require(SwipeKeyMap(letterKeys: SwipeGrid.qwertz))
        let readings = vocabulary.readings(
            SwipeGrid.stroke(word, on: map),
            keys: map.keys,
            previous: nil
        )
        #expect(readings.first == word)
    }

    @Test func listedWordsAreNeverRead() throws {
        let vocabulary = try #require(SwipeTestVocabulary.english)
        let map = try #require(SwipeKeyMap(letterKeys: SwipeGrid.qwerty))
        let readings = vocabulary.readings(
            SwipeGrid.stroke("damn", on: map),
            keys: map.keys,
            previous: nil
        )
        #expect(!readings.isEmpty)
        #expect(!readings.contains("damn"))
    }

    @Test func onlyBundledLanguagesHaveAVocabulary() {
        #expect(SwipeVocabulary(languageCode: "fr") == nil)
        #expect(SwipeVocabulary.language(for: "de_CH") == "de")
        #expect(SwipeVocabulary.language(for: "EN-gb") == "en")
    }

    // MARK: - Spelling
    @Test func englishCapitalisesI() throws {
        let vocabulary = try #require(SwipeTestVocabulary.english)
        #expect(vocabulary.spelling(of: "i'm", after: nil) == "I'm")
        #expect(vocabulary.spelling(of: "ice", after: nil) == "ice")
    }

    @Test func germanNounsTakeTheirCapital() throws {
        let vocabulary = try #require(SwipeTestVocabulary.german)
        #expect(vocabulary.spelling(of: "haus", after: nil) == "Haus")
        #expect(vocabulary.spelling(of: "leben", after: "zu") == "leben")
        #expect(vocabulary.spelling(of: "leben", after: "das") == "Leben")
        #expect(vocabulary.spelling(of: "und", after: nil) == "und")
    }

    @Test func previousWordIsTheWordRightBeforeTheCursor() {
        #expect(SwipeVocabulary.previousWord(before: "Hello World ") == "world")
        #expect(SwipeVocabulary.previousWord(before: "Hello wor") == "wor")
        #expect(SwipeVocabulary.previousWord(before: "It’s ") == "it's")
        #expect(SwipeVocabulary.previousWord(before: "Done. ") == nil)
        #expect(SwipeVocabulary.previousWord(before: "") == nil)
    }

    // MARK: - Key Map
    @Test func pitchIsTheDistanceBetweenNeighbouringKeys() throws {
        let map = try #require(SwipeKeyMap(letterKeys: SwipeGrid.qwerty))
        #expect(map.keys.pitch == CGSize(width: 40, height: 40))
        #expect(map.keys.centres["q"] == CGPoint(x: 79, y: 98.5))
        #expect(map.isNearLetters(CGPoint(x: 100, y: 120)))
        #expect(map.isNearLetters(CGPoint(x: 113, y: 250)))
        #expect(!map.isNearLetters(CGPoint(x: 113, y: 270)))
    }
}

// MARK: - SwipePathFilterTests
struct SwipePathFilterTests {
    @Test func backAndForthJankIsCutOutWithItsTime() {
        // Rightwards at 4 pt a step, a jank back 24 pt and forward again at x = 100.
        var xs = Array(stride(from: 0.0, through: 100, by: 4))
        xs += [92, 84, 76, 84, 92, 100]
        xs += Array(stride(from: 104.0, through: 200, by: 4))
        let (points, times) = path(xs.map { CGPoint(x: $0, y: 0) })
        let filtered = SwipePathFilter.withoutJank(points, times: times, pitch: 40)
        #expect(zip(filtered.points, filtered.points.dropFirst()).allSatisfy { $1.x > $0.x })
        #expect(filtered.points.last == CGPoint(x: 200, y: 0))
        #expect((filtered.times.last ?? 0) < (times.last ?? 0) - 0.04)
    }

    @Test func aWordsOwnReversalStays() {
        // Out to a letter and back past where the path came from, as "and" turns at n.
        let out = stride(from: 0.0, through: 80, by: 4).map { CGPoint(x: $0, y: 0) }
        let back = stride(from: 76.0, through: 20, by: -4).map { CGPoint(x: $0, y: 1) }
        let (points, times) = path(out + back)
        #expect(SwipePathFilter.withoutJank(points, times: times, pitch: 40).points == points)
    }

    @Test func aReversalAtTheStartStays() {
        // Out a little and back to where the press went down, as "pop" starts.
        let xs: [Double] = [0, 6, 12, 18, 24, 18, 12, 6, 1, 0.5]
        let (points, times) = path(xs.map { CGPoint(x: $0, y: 0) })
        #expect(SwipePathFilter.withoutJank(points, times: times, pitch: 40).points == points)
    }

    @Test func aJankedSwipeStillReadsItsWord() throws {
        let vocabulary = try #require(SwipeTestVocabulary.english)
        let map = try #require(SwipeKeyMap(letterKeys: SwipeGrid.qwerty))
        let clean = SwipeGrid.stroke("typing", on: map)
        // Partway along, the pointer jumps back more than half a key and returns: read as it
        // came, the path says "topping".
        let at = clean.points.count * 2 / 5
        let heading = CGPoint(
            x: clean.points[at].x - clean.points[at - 3].x,
            y: clean.points[at].y - clean.points[at - 3].y
        )
        let length = hypot(heading.x, heading.y)
        let far = CGPoint(
            x: clean.points[at].x - heading.x / length * 24,
            y: clean.points[at].y - heading.y / length * 24
        )
        var janked = SwipeStroke()
        for i in 0...at { janked.add(clean.points[i], at: clean.times[i]) }
        let base = clean.times[at]
        for k in 1...4 {
            let f = CGFloat(k) / 4
            let p = CGPoint(
                x: clean.points[at].x + (far.x - clean.points[at].x) * f,
                y: clean.points[at].y + (far.y - clean.points[at].y) * f
            )
            janked.add(p, at: base + Double(k) * 0.008)
        }
        for k in 1...4 {
            let f = CGFloat(k) / 4
            let p = CGPoint(
                x: far.x + (clean.points[at].x - far.x) * f,
                y: far.y + (clean.points[at].y - far.y) * f
            )
            janked.add(p, at: base + 0.032 + Double(k) * 0.008)
        }
        for i in (at + 1)..<clean.points.count {
            janked.add(clean.points[i], at: clean.times[i] + 0.064)
        }
        let readings = vocabulary.readings(janked, keys: map.keys, previous: nil)
        #expect(readings.first == "typing")
    }

    private func path(_ points: [CGPoint]) -> ([CGPoint], [TimeInterval]) {
        (points, points.indices.map { Double($0) * 0.008 })
    }
}

// MARK: - SwipeTypingControllerTests
@MainActor
struct SwipeTypingControllerTests {
    // MARK: - Eligibility
    @Test func onlyPlainLetterPressesMayBecomeSwipes() {
        let controller = makeController()
        let a = SwipeGrid.buttons.first { $0.id == "a" }!
        #expect(controller.begin(buttonID: "a", action: a.primaryAction, at: .zero, time: 0))
        let command = KeyAction.keyStroke(KeyStroke(.a, modifiers: [.command]))
        #expect(!controller.begin(buttonID: "a", action: command, at: .zero, time: 0))
        let shift = KeyAction.keyStroke(KeyStroke(.a, modifiers: [.shift]))
        #expect(controller.begin(buttonID: "a", action: shift, at: .zero, time: 0))
        #expect(
            !controller.begin(
                buttonID: "space",
                action: .keyStroke(KeyStroke(.space)),
                at: .zero,
                time: 0
            )
        )
    }

    @Test func disabledOrBlockedInputNeverSwipes() {
        var enabled = false
        var allowed = true
        let controller = makeController(enabled: { enabled }, allowed: { allowed })
        let action = KeyAction.keyStroke(KeyStroke(.a))
        #expect(!controller.begin(buttonID: "a", action: action, at: .zero, time: 0))
        enabled = true
        allowed = false
        #expect(!controller.begin(buttonID: "a", action: action, at: .zero, time: 0))
        allowed = true
        #expect(controller.begin(buttonID: "a", action: action, at: .zero, time: 0))
        controller.configure(panel: nil)
        #expect(!controller.begin(buttonID: "a", action: action, at: .zero, time: 0))
    }

    // MARK: - Outcomes
    @Test func aPressThatNeverTravelsIsNoSwipe() throws {
        let controller = makeController()
        let start = try #require(SwipeGrid.centre("a"))
        #expect(begin(controller, "a", at: start))
        #expect(
            !controller.move(buttonID: "a", to: CGPoint(x: start.x + 12, y: start.y), time: 0.1)
        )
        #expect(controller.trail.isEmpty)
        let outcome = controller.finish(buttonID: "a", at: start, time: 0.2, previous: nil)
        #expect(outcome == .notSwiped)
    }

    @Test func aSwipeReadsItsWordAndDrawsItsTrail() throws {
        let controller = makeController()
        let stroke = try strokeOnGrid("hello")
        #expect(begin(controller, "h", at: stroke.points[0]))
        var swiping = false
        for (point, time) in zip(stroke.points, stroke.times).dropFirst() {
            swiping = controller.move(buttonID: "h", to: point, time: time)
        }
        #expect(swiping)
        #expect(controller.trail.count > 2)
        let end = try #require(stroke.points.last)
        let outcome = controller.finish(buttonID: "h", at: end, time: 1, previous: nil)
        guard case .words(let words) = outcome else {
            Issue.record("Expected words, got \(outcome)")
            return
        }
        #expect(words.first == "hello")
        #expect(controller.trail.isEmpty)
    }

    @Test func aSwipeBackToItsKeyIsATap() throws {
        let controller = makeController()
        let a = try #require(SwipeGrid.centre("a"))
        #expect(begin(controller, "a", at: a))
        #expect(controller.move(buttonID: "a", to: CGPoint(x: a.x + 45, y: a.y), time: 0.1))
        let outcome = controller.finish(buttonID: "a", at: a, time: 0.2, previous: nil)
        #expect(outcome == .tap)
    }

    @Test func aSwipeReleasedAwayFromTheLettersTypesNothing() throws {
        let controller = makeController()
        let stroke = try strokeOnGrid("hello")
        #expect(begin(controller, "h", at: stroke.points[0]))
        for (point, time) in zip(stroke.points, stroke.times).dropFirst() {
            _ = controller.move(buttonID: "h", to: point, time: time)
        }
        let away = CGPoint(x: 300, y: 400)
        _ = controller.move(buttonID: "h", to: away, time: 1)
        #expect(controller.finish(buttonID: "h", at: away, time: 1.1, previous: nil) == .nothing)
    }

    // MARK: - Fixtures
    private func makeController(
        enabled: @escaping () -> Bool = { true },
        allowed: @escaping () -> Bool = { true }
    ) -> SwipeTypingController {
        let controller = SwipeTypingController(
            enabled: enabled,
            inputAllowed: allowed,
            language: { ("com.apple.keylayout.US", "en") },
            letter: { SwipeGrid.letter(for: $0) },
            vocabulary: { SwipeTestVocabulary.named($0) }
        )
        controller.configure(panel: SwipeGrid.panel)
        return controller
    }

    private func begin(_ controller: SwipeTypingController, _ id: String, at point: CGPoint) -> Bool
    {
        let button = SwipeGrid.buttons.first { $0.id == id }!
        return controller.begin(buttonID: id, action: button.primaryAction, at: point, time: 0)
    }

    private func strokeOnGrid(_ word: String) throws -> SwipeStroke {
        SwipeGrid.stroke(word, on: try #require(SwipeKeyMap(letterKeys: SwipeGrid.qwerty)))
    }
}

// MARK: - SwipeTestVocabulary
/// Each bundled vocabulary, loaded once for all the tests that read swipes.
enum SwipeTestVocabulary {
    static let english = SwipeVocabulary(languageCode: "en")
    static let german = SwipeVocabulary(languageCode: "de")

    static func named(_ language: String) -> SwipeVocabulary? {
        switch language {
        case "en": english
        case "de": german
        default: nil
        }
    }
}

// MARK: - SwipeGrid
/// A Mac keyboard's letter rows as a Panel Editor panel lays them out: 38 × 37 pt keys on a
/// 40 pt pitch, each row staggered as on the hardware.
enum SwipeGrid {
    static let qwerty = letterKeys(rows: ["qwertyuiop", "asdfghjkl", "zxcvbnm"])
    /// German QWERTZ, with ß on the number row as on the hardware.
    static let qwertz =
        letterKeys(rows: ["qwertzuiopü", "asdfghjklöä", "yxcvbnm"])
        + [SwipeKeyMap.LetterKey(id: "ß", frame: frame(x: 459, y: 58.5), letter: "ß")]

    private static func letterKeys(rows: [String]) -> [SwipeKeyMap.LetterKey] {
        let starts: [CGFloat] = [79, 89, 113]
        return rows.enumerated().flatMap { row, letters in
            letters.enumerated().map { column, letter in
                SwipeKeyMap.LetterKey(
                    id: String(letter),
                    frame: frame(
                        x: starts[row] + CGFloat(column) * 40,
                        y: 98.5 + CGFloat(row) * 40
                    ),
                    letter: letter
                )
            }
        }
    }

    private static func frame(x: CGFloat, y: CGFloat) -> CGRect {
        CGRect(x: x - 19, y: y - 18.5, width: 38, height: 37)
    }

    static func centre(_ letter: Character) -> CGPoint? {
        qwerty.first { $0.letter == letter }.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
    }

    /// A drag through `word`'s keys at an even speed, a point every 4 pt and 8 ms.
    static func stroke(_ word: String, on map: SwipeKeyMap) -> SwipeStroke {
        let centres = word.compactMap { map.keys.centres[$0] }
        var stroke = SwipeStroke(centres[0], at: 0)
        var time: TimeInterval = 0
        for (from, to) in zip(centres, centres.dropFirst()) {
            let steps = max(1, Int(hypot(to.x - from.x, to.y - from.y) / 4))
            for step in 1...steps {
                let fraction = CGFloat(step) / CGFloat(steps)
                time += 0.008
                stroke.add(
                    CGPoint(
                        x: from.x + fraction * (to.x - from.x),
                        y: from.y + fraction * (to.y - from.y)
                    ),
                    at: time
                )
            }
        }
        return stroke
    }

    // MARK: - Panel
    /// The QWERTY letters as panel buttons that press each letter's key, plus a space bar.
    static let buttons: [PanelEditorButton] =
        qwerty.map { key in
            button(
                id: key.id,
                frame: key.frame,
                action: .keyStroke(KeyStroke(Key.letter(key.letter)!))
            )
        } + [
            button(
                id: "space",
                frame: CGRect(x: 150, y: 200, width: 200, height: 37),
                action: .keyStroke(KeyStroke(.space))
            )
        ]

    static let panel = PanelEditorPanel(
        id: "swipe-panel",
        rawIdentifier: "swipe-panel",
        profileDisplayName: "Fixture",
        name: "Letters",
        displayOrder: 0,
        size: CGSize(width: 520, height: 260),
        isDefaultHomePanel: true,
        associatedApplicationBundleIdentifiers: [],
        buttons: buttons
    )

    static func letter(for key: Key) -> Character? {
        Key.letterKeys[key]
    }

    private static func button(id: String, frame: CGRect, action: KeyAction) -> PanelEditorButton {
        PanelEditorButton(
            id: id,
            frame: frame,
            title: id,
            secondaryTitle: nil,
            fontSize: 12,
            backgroundColor: nil,
            foregroundColor: nil,
            shape: .rectangle,
            primaryAction: action,
            secondaryAction: .none,
            pressBehavior: .pressAndRelease
        )
    }
}

// MARK: - US Letter Keys
extension Key {
    /// The US layout's letter on each letter key.
    fileprivate static let letterKeys: [Key: Character] = [
        .a: "a", .b: "b", .c: "c", .d: "d", .e: "e", .f: "f", .g: "g", .h: "h", .i: "i",
        .j: "j", .k: "k", .l: "l", .m: "m", .n: "n", .o: "o", .p: "p", .q: "q", .r: "r",
        .s: "s", .t: "t", .u: "u", .v: "v", .w: "w", .x: "x", .y: "y", .z: "z",
    ]

    fileprivate static func letter(_ letter: Character) -> Key? {
        letterKeys.first { $0.value == letter }?.key
    }
}
