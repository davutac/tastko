import SwiftUI

// MARK: - SwipeTrailView
/// The path of the swipe under way, drawn over the keys. Reading the trail here keeps the
/// pointer's moves from redrawing the keys themselves.
struct SwipeTrailView: View {
    let controller: SwipeTypingController
    /// The panel point at the view's top-left corner.
    let origin: CGPoint
    let scale: CGFloat

    @Environment(\.keyboardPalette) private var palette

    // MARK: - Body
    var body: some View {
        let trail = controller.trail
        Canvas { context, _ in
            guard trail.count >= 2 else { return }
            var path = Path()
            path.addLines(
                trail.map { point in
                    CGPoint(x: (point.x - origin.x) * scale, y: (point.y - origin.y) * scale)
                }
            )
            context.stroke(
                path,
                with: .color(palette.active.opacity(0.55)),
                style: StrokeStyle(lineWidth: 6 * scale, lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
