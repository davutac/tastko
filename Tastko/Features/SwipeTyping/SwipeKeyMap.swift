import CoreGraphics
import Foundation

// MARK: - SwipeKeyMap
/// A panel's letter keys for swipe typing, in panel coordinates: which button types which
/// letter, each key's frame, and the decoder's key centres and pitch.
nonisolated struct SwipeKeyMap: Equatable, Sendable {
    /// A panel button that types one letter of the language's alphabet.
    struct LetterKey: Equatable, Sendable {
        let id: String
        let frame: CGRect
        let letter: Character
    }

    let keys: SwipeDecoder.Keys
    private let letterKeys: [LetterKey]
    private let lettersByID: [String: Character]

    /// How far from the nearest letter key's centre, in pitches, a swipe may end and still
    /// type: past it the pointer clearly left the letters, which cancels the swipe. The decoder
    /// itself takes last letters up to 2.1 pitches from where the pointer was released.
    static let releaseReach = 2.0

    // MARK: - Building
    /// The map for `letterKeys`, or nil with fewer than two distinct letters. When two buttons
    /// type the same letter, the first one's centre is the decoder's.
    init?(letterKeys: [LetterKey]) {
        var centres: [Character: CGPoint] = [:]
        for key in letterKeys where centres[key.letter] == nil {
            centres[key.letter] = CGPoint(x: key.frame.midX, y: key.frame.midY)
        }
        guard centres.count >= 2 else { return nil }
        self.letterKeys = letterKeys
        lettersByID = Dictionary(
            letterKeys.map { ($0.id, $0.letter) },
            uniquingKeysWith: { first, _ in first }
        )
        keys = SwipeDecoder.Keys(centres: centres, pitch: Self.pitch(of: letterKeys))
    }

    // MARK: - Lookup
    func letter(for buttonID: String) -> Character? {
        lettersByID[buttonID]
    }

    /// The letter key under `point`, if any.
    func letterKey(at point: CGPoint) -> LetterKey? {
        letterKeys.first { $0.frame.contains(point) }
    }

    /// Whether `point` lies within `releaseReach` pitches of a letter key's centre.
    func isNearLetters(_ point: CGPoint) -> Bool {
        let pitch = keys.pitch
        guard pitch.width > 0, pitch.height > 0 else { return false }
        return keys.centres.values.contains { centre in
            let dx = (point.x - centre.x) / pitch.width
            let dy = (point.y - centre.y) / pitch.height
            return (dx * dx + dy * dy).squareRoot() <= Self.releaseReach
        }
    }

    // MARK: - Pitch
    /// The distance between neighbouring keys' centres: across, the median gap to the nearest
    /// key to the right in the same row; down, the median gap between rows. A key's own size
    /// stands in when the panel has no neighbour that way.
    static func pitch(of letterKeys: [LetterKey]) -> CGSize {
        let frames = letterKeys.map(\.frame)
        let typical = CGSize(
            width: median(frames.map(\.width)) ?? 1,
            height: median(frames.map(\.height)) ?? 1
        )
        var across: [CGFloat] = []
        for frame in frames {
            let right = frames.compactMap { other -> CGFloat? in
                let dx = other.midX - frame.midX
                return dx > 0 && abs(other.midY - frame.midY) < typical.height / 2 ? dx : nil
            }
            if let nearest = right.min() { across.append(nearest) }
        }
        var rows: [CGFloat] = []
        for y in frames.map(\.midY).sorted()
        where rows.last.map({ y - $0 >= typical.height / 2 }) ?? true {
            rows.append(y)
        }
        let down = zip(rows, rows.dropFirst()).map { $1 - $0 }
        return CGSize(
            width: median(across) ?? typical.width,
            height: median(down) ?? typical.height
        )
    }

    private static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }
}
