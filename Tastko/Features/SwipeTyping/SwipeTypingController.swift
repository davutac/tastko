import Carbon
import CoreGraphics
import Defaults
import Observation

// MARK: - SwipeOutcome
/// What a letter press that may have been a swipe comes to when the pointer is released.
enum SwipeOutcome: Equatable {
    /// The pointer never travelled a key's pitch: the press is a tap.
    case notSwiped
    /// A swipe that came back to its key: the key's letter goes in, as a tap's would.
    case tap
    /// Readings to type, best first, spelled as the language writes them.
    case words([String])
    /// A swipe that read as no word, or ended away from the letters: nothing goes in.
    case nothing
}

// MARK: - SwipeTypingController
/// Swipe typing: press a letter, move the pointer through a word's letters, and release, and the
/// word goes in. A letter press becomes a swipe once the pointer travels more than a key's pitch
/// from where it went down; until then it is an ordinary press that types on release.
///
/// The controller knows the shown panel's letter keys and the language's vocabulary, follows
/// the pointer, and reads the path when the press ends. `KeyInputController` decides what a
/// press types and inserts the word.
@Observable
@MainActor
final class SwipeTypingController {
    static let shared = SwipeTypingController()

    /// The swipe under way's path, in panel coordinates; empty when none is.
    private(set) var trail: [CGPoint] = []

    /// How far (key pitches) a swipe may go from where it went down and still be a tap that
    /// slid, when it ends on the key it started on.
    static let slidTapReach: CGFloat = 1.6

    @ObservationIgnored private let enabled: () -> Bool
    @ObservationIgnored private let inputAllowed: () -> Bool
    @ObservationIgnored private let language: () -> (id: String, code: String)?
    @ObservationIgnored private let letter: (Key) -> Character?
    @ObservationIgnored private let loadVocabulary: (String) -> SwipeVocabulary?
    @ObservationIgnored private var panel: PanelEditorPanel?
    @ObservationIgnored private var prepared: Prepared?
    @ObservationIgnored private var vocabularies: [String: SwipeVocabulary?] = [:]
    @ObservationIgnored private var press: Press?

    // MARK: - State
    /// The shown panel's letter keys and vocabulary, for the panel and language they were
    /// built for.
    private struct Prepared {
        let panelID: String
        let languageID: String
        let map: SwipeKeyMap?
        let vocabulary: SwipeVocabulary?
    }

    /// A letter press that may become, or is, a swipe.
    private struct Press {
        let buttonID: String
        let map: SwipeKeyMap
        let vocabulary: SwipeVocabulary
        var stroke: SwipeStroke
        var isSwiping = false
    }

    // MARK: - Initialization
    init(
        enabled: @escaping () -> Bool = { Defaults[.swipeTypingEnabled] },
        inputAllowed: @escaping () -> Bool = { SwipeTypingController.systemAllowsSwipes() },
        language: @escaping () -> (id: String, code: String)? = {
            let language = KeyboardLanguageService.shared.selectedLanguage
            guard let language, let code = language.languageCodes.first else { return nil }
            return (language.id, code)
        },
        letter: @escaping (Key) -> Character? = { key in
            KeyboardLanguageService.shared.keyLabels.label(for: KeyStroke(key))
                .flatMap { SwipeTypingController.letter(fromLabel: $0.title) }
        },
        vocabulary: @escaping (String) -> SwipeVocabulary? = {
            SwipeVocabulary(languageCode: $0)
        }
    ) {
        self.enabled = enabled
        self.inputAllowed = inputAllowed
        self.language = language
        self.letter = letter
        self.loadVocabulary = vocabulary
    }

    // MARK: - Panel
    /// The panel the keyboard shows, or nil where swipes must not start (the login window).
    /// Prepares its letter keys and vocabulary ahead of the first press.
    func configure(panel: PanelEditorPanel?) {
        cancel()
        self.panel = panel
        // A reloaded profile keeps its panel's ID, so its keys are read again.
        prepared = nil
        _ = current()
    }

    /// The shown panel's letter keys and vocabulary for the selected language, rebuilt when
    /// either changed.
    private func current() -> (map: SwipeKeyMap, vocabulary: SwipeVocabulary)? {
        guard let panel, let language = language() else { return nil }
        if let prepared, prepared.panelID == panel.id, prepared.languageID == language.id {
            guard let map = prepared.map, let vocabulary = prepared.vocabulary else { return nil }
            return (map, vocabulary)
        }
        let vocabulary = vocabulary(for: language.code)
        let map = vocabulary.flatMap { keyMap(for: panel, alphabet: $0.alphabet) }
        prepared = Prepared(
            panelID: panel.id,
            languageID: language.id,
            map: map,
            vocabulary: vocabulary
        )
        guard let map, let vocabulary else { return nil }
        return (map, vocabulary)
    }

    private func vocabulary(for code: String) -> SwipeVocabulary? {
        guard let language = SwipeVocabulary.language(for: code) else { return nil }
        if let loaded = vocabularies[language] { return loaded }
        let loaded = loadVocabulary(language)
        vocabularies[language] = loaded
        return loaded
    }

    /// The panel's buttons that type a single letter of `alphabet` with no modifier.
    private func keyMap(for panel: PanelEditorPanel, alphabet: Set<Character>) -> SwipeKeyMap? {
        SwipeKeyMap(
            letterKeys: panel.visibleButtons.compactMap { button in
                guard case .keyStroke(let stroke) = button.primaryAction, stroke.modifiers.isEmpty,
                    let letter = letter(stroke.key), alphabet.contains(letter)
                else { return nil }
                return SwipeKeyMap.LetterKey(id: button.id, frame: button.frame, letter: letter)
            }
        )
    }

    /// A key label's letter, lowercase, when it is a single letter.
    nonisolated static func letter(fromLabel title: String) -> Character? {
        let lower = title.lowercased()
        guard lower.count == 1, let letter = lower.first, letter.isLetter else { return nil }
        return letter
    }

    // MARK: - Eligibility
    /// Secure input (a password field) and the lock screen never take swipes, and neither does
    /// a physically held shortcut modifier.
    static func systemAllowsSwipes() -> Bool {
        let shortcuts: CGEventFlags = [
            .maskCommand, .maskAlternate, .maskControl, .maskSecondaryFn,
        ]
        return !IsSecureEventInputEnabled() && !KeyboardService.shared.isScreenLocked
            && CGEventSource.flagsState(.combinedSessionState).intersection(shortcuts).isEmpty
    }

    // MARK: - Press Lifecycle
    /// A press went down on `buttonID` at `point` (panel coordinates). True when it may become
    /// a swipe: then its letter waits for the release. `action` is what the press would type.
    func begin(
        buttonID: String,
        action: KeyAction,
        at point: CGPoint,
        time: TimeInterval
    ) -> Bool {
        cancel()
        guard enabled(), case .keyStroke(let stroke) = action,
            stroke.modifiers.intersection([.command, .control, .option, .function]).isEmpty,
            inputAllowed(), let current = current(), current.map.letter(for: buttonID) != nil
        else { return false }
        press = Press(
            buttonID: buttonID,
            map: current.map,
            vocabulary: current.vocabulary,
            stroke: SwipeStroke(point, at: time)
        )
        return true
    }

    /// The pointer moved while `buttonID` is pressed. True once the press is a swipe.
    func move(buttonID: String, to point: CGPoint, time: TimeInterval) -> Bool {
        guard var press, press.buttonID == buttonID else { return false }
        press.stroke.add(point, at: time)
        if press.isSwiping {
            trail.append(point)
        }
        else if let origin = press.stroke.points.first,
            hypot(point.x - origin.x, point.y - origin.y) > press.map.keys.pitch.width
        {
            press.isSwiping = true
            trail = press.stroke.points
        }
        self.press = press
        return press.isSwiping
    }

    /// Whether `buttonID`'s press is under way, as a swipe or one that may become one.
    func isTracking(_ buttonID: String) -> Bool {
        press?.buttonID == buttonID
    }

    /// The pointer was released at `point`. `previous` is the word before the cursor, which
    /// weighs the readings and spells a German noun.
    func finish(
        buttonID: String,
        at point: CGPoint,
        time: TimeInterval,
        previous: String?
    ) -> SwipeOutcome {
        guard var press, press.buttonID == buttonID else { return .notSwiped }
        self.press = nil
        trail = []
        guard press.isSwiping else { return .notSwiped }
        press.stroke.add(point, at: time)
        let readings = press.vocabulary.readings(
            press.stroke,
            keys: press.map.keys,
            previous: previous
        )
        if let letter = slidTapLetter(press),
            readings.first.map({ !Self.word($0, startsAndEndsWith: letter) }) ?? true
        {
            return .tap
        }
        guard press.map.isNearLetters(point), !readings.isEmpty else { return .nothing }
        return .words(readings.map { press.vocabulary.spelling(of: $0, after: previous) })
    }

    /// Drops the press under way, if any: nothing goes in.
    func cancel() {
        press = nil
        if !trail.isEmpty { trail = [] }
    }

    // MARK: - Slid Taps
    /// The letter of a swipe that came back to the key it went down on without going more than
    /// `slidTapReach` pitches from it ("a" dragged a little too far and back); nil otherwise.
    private func slidTapLetter(_ press: Press) -> Character? {
        let points = press.stroke.points
        guard let first = points.first, let last = points.last,
            let down = press.map.letterKey(at: first),
            press.map.letterKey(at: last) == down
        else { return nil }
        let reach = press.map.keys.pitch.width * Self.slidTapReach
        guard points.allSatisfy({ hypot($0.x - first.x, $0.y - first.y) <= reach }) else {
            return nil
        }
        return down.letter
    }

    /// Whether `word` begins and ends on `letter`'s key ("lol" on l): a word a swipe that comes
    /// back to its key can mean.
    nonisolated static func word(_ word: String, startsAndEndsWith letter: Character) -> Bool {
        func base(_ character: Character?) -> Character? {
            character.flatMap {
                String($0).lowercased().decomposedStringWithCanonicalMapping.first
            }
        }
        let key = base(letter)
        return word.count > 1 && base(word.first) == key && base(word.last) == key
    }
}
