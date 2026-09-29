import SwiftUI

// MARK: - PanelEditorISOEnterMetrics
/// Panel Editor's ISO Return is a 46 × 77 frame whose lower part starts where the key to
/// its left ends (8) plus the 2-point gap Panel Editor leaves between keys.
nonisolated enum PanelEditorISOEnterMetrics {
    nonisolated static let lowerLeadingInsetFraction: CGFloat = 10 / 46
    nonisolated static let upperHeightFraction: CGFloat = 37 / 77
}

// MARK: - PanelEditorKeyShape
struct PanelEditorKeyShape: Shape {
    let buttonShape: PanelEditorButtonShape
    var cornerRadius: CGFloat = 0
    /// How far `rect` is already inset from the button's frame. The notch edges move in by
    /// the same amount, so the gaps beside them match the gaps between other keys.
    var frameInset: CGFloat = 0

    // MARK: - Path
    nonisolated func path(in rect: CGRect) -> Path {
        switch buttonShape {
        case .rectangle:
            return KeycapShape(cornerRadius: cornerRadius).path(in: rect)
        case .isoReturn:
            // Measured on the button's frame, then moved in by `frameInset` like the outer edges.
            let lowerLeadingInset =
                (rect.width + 2 * frameInset) * PanelEditorISOEnterMetrics.lowerLeadingInsetFraction
            let upperSectionHeight =
                (rect.height + 2 * frameInset) * PanelEditorISOEnterMetrics.upperHeightFraction
                - 2 * frameInset
            let corners = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX + lowerLeadingInset, y: rect.maxY),
                CGPoint(x: rect.minX + lowerLeadingInset, y: rect.minY + upperSectionHeight),
                CGPoint(x: rect.minX, y: rect.minY + upperSectionHeight),
            ]
            var path = Path()
            if cornerRadius > 0 {
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + upperSectionHeight / 2))
                for index in corners.indices {
                    path.addArc(
                        tangent1End: corners[index],
                        tangent2End: corners[(index + 1) % corners.count],
                        radius: min(cornerRadius, lowerLeadingInset / 2)
                    )
                }
            }
            else {
                path.move(to: corners[0])
                for corner in corners.dropFirst() {
                    path.addLine(to: corner)
                }
            }
            path.closeSubpath()
            return path
        }
    }
}
