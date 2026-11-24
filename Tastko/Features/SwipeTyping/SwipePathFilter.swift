import CoreGraphics
import Foundation

// MARK: - SwipePathFilter
/// Takes jank out of a pointer's path before the decoder reads it. A mouse, trackpad or head
/// pointer jerks back and forth where a finger glides, and the decoder reads every sharp
/// reversal as a turn some letter of the word must explain, so one jank can cost the right word.
///
/// A stretch where the pointer goes back against the way it was heading and then comes forward
/// to where it was, within `reach` key pitches of travel, is cut out, and the time it took with
/// it. A word's own reversals stay: they go ahead to a letter and back ("and" turns back at n),
/// or start the path ("pop"). Measured on Hex's synthetic swipe paths with simulated janks added
/// (a benchmark outside this repository), it recovered most of the words the janks cost and left
/// clean paths' readings as they were.
nonisolated enum SwipePathFilter {
    /// The longest jank cut out, in key pitches of travel there and back.
    static let reach = 1.6
    /// How close (pitches) the pointer must come back to an earlier point.
    static let returnRadius = 0.25
    /// How far behind (pitches) the point where it was heading the pointer must have gone.
    static let backDistance = 0.15
    /// How much path before a point says which way the pointer was heading there: short, so
    /// that just past a corner it is the new way, not a chord across the corner.
    static let headingLength = 0.12

    // MARK: - Filtering
    /// `points` (with their `times`) without back-and-forth janks. `pitch` is the distance
    /// between neighbouring keys' centres, in the points' units.
    static func withoutJank(
        _ points: [CGPoint],
        times: [TimeInterval],
        pitch: Double,
        reach: Double = reach
    ) -> (points: [CGPoint], times: [TimeInterval]) {
        guard points.count == times.count, points.count >= 3, pitch > 0 else {
            return (points, times)
        }
        var kept: [CGPoint] = [points[0]]
        var keptTimes: [TimeInterval] = [times[0]]
        var arcs: [Double] = [0]
        var pending: TimeInterval = 0
        let radius = returnRadius * pitch
        let window = reach * pitch
        for i in 1..<points.count {
            pending += max(0, times[i] - times[i - 1])
            let point = points[i]
            let step = distance(kept[kept.count - 1], point)
            // A still pointer sends no new place: its time goes to the next point's step.
            guard step > 1e-6 * pitch else { continue }
            let arc = arcs[arcs.count - 1] + step
            // The earliest kept point within `reach` of travel the pointer came back to, after
            // going back behind it.
            var loopStart: Int?
            var j = kept.count - 1
            while j >= 0, arc - arcs[j] <= window {
                if arc - arcs[j] >= 2.5 * radius, distance(kept[j], point) <= radius,
                    wentBack(from: j, kept: kept, arcs: arcs, to: point, pitch: pitch)
                {
                    loopStart = j
                }
                j -= 1
            }
            if let loopStart {
                kept.removeSubrange((loopStart + 1)...)
                keptTimes.removeSubrange((loopStart + 1)...)
                arcs.removeSubrange((loopStart + 1)...)
                // Back where the jank began: nothing new to keep, and its time is gone.
                if distance(kept[kept.count - 1], point) <= 1e-6 * pitch {
                    pending = 0
                    continue
                }
            }
            let time = keptTimes[keptTimes.count - 1] + pending
            pending = 0
            arcs.append(arcs[arcs.count - 1] + distance(kept[kept.count - 1], point))
            kept.append(point)
            keptTimes.append(time)
        }
        return (kept, keptTimes)
    }

    // MARK: - Reversals
    /// Whether the pointer, between kept point `j` and `point`, went back behind `j` against
    /// the way it was heading there and then came forward again. A word that reverses at a
    /// letter goes ahead and comes back past `j`, which this leaves alone, and the start of the
    /// path has no heading yet.
    private static func wentBack(
        from j: Int,
        kept: [CGPoint],
        arcs: [Double],
        to point: CGPoint,
        pitch: Double
    ) -> Bool {
        var k = j
        while k > 0, arcs[j] - arcs[k] < headingLength * pitch { k -= 1 }
        let dx = kept[j].x - kept[k].x
        let dy = kept[j].y - kept[k].y
        let length = hypot(dx, dy)
        guard arcs[j] - arcs[k] >= headingLength * pitch, length > 0 else { return false }
        func ahead(_ p: CGPoint) -> Double {
            ((p.x - kept[j].x) * dx + (p.y - kept[j].y) * dy) / length
        }
        guard let farthestBack = kept[(j + 1)...].map(ahead).min() else { return false }
        let back = backDistance * pitch
        return farthestBack < -back && ahead(point) - farthestBack > back
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }
}
