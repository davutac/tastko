import SwiftUI

// MARK: - Child Window Identity
nonisolated struct ChildWindowID: Hashable, Sendable {
    let rawValue: String

    // MARK: - Initialization
    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

// MARK: - Child Window Configuration
struct ChildWindowConfiguration {
    enum Edge { case top, bottom, left, right }
    enum Alignment { case start, center, end }
    enum Size {
        case fixed(CGSize)
        /// Fits the content, including insets, up to the parent window width.
        case contentWidth(height: CGFloat)
        /// Fits both content dimensions, with width capped at the parent width.
        case content
        /// Matches the parent width; omitted height fits the content.
        case parentWidth(height: CGFloat? = nil)
        case parentHeight(width: CGFloat)
    }

    var title = ""
    var edge: Edge = .top
    var alignment: Alignment = .center
    var size: Size = .parentWidth(height: 44)
    var gap: CGFloat = 8
    /// Screen-coordinate offset: positive x moves right; positive y moves up.
    var offset: CGSize = .zero
    var style = ChildWindowStyle()
    var ignoresMouseEvents = false
    var passesThroughEmptyArea = false

    // MARK: - Geometry
    func frame(relativeTo parent: CGRect, contentSize: CGSize = CGSize(width: 1, height: 1))
        -> CGRect
    {
        let resolvedSize: CGSize
        switch size {
        case .fixed(let value): resolvedSize = value
        case .contentWidth(let height):
            resolvedSize = CGSize(width: min(parent.width, contentSize.width), height: height)
        case .content:
            resolvedSize = CGSize(
                width: min(parent.width, contentSize.width),
                height: contentSize.height
            )
        case .parentWidth(let height):
            resolvedSize = CGSize(width: parent.width, height: height ?? contentSize.height)
        case .parentHeight(let width):
            resolvedSize = CGSize(width: width, height: parent.height)
        }
        let width = resolvedSize.width.isFinite ? max(1, resolvedSize.width) : 1
        let height = resolvedSize.height.isFinite ? max(1, resolvedSize.height) : 1
        let spacing = gap.isFinite ? max(0, gap) : 0
        let fraction: CGFloat =
            switch alignment {
            case .start: 0
            case .center: 0.5
            case .end: 1
            }
        var origin: CGPoint
        switch edge {
        case .top, .bottom:
            origin = CGPoint(
                x: parent.minX + (parent.width - width) * fraction,
                y: edge == .top ? parent.maxY + spacing : parent.minY - spacing - height
            )
        case .left, .right:
            origin = CGPoint(
                x: edge == .right ? parent.maxX + spacing : parent.minX - spacing - width,
                y: parent.maxY - height - (parent.height - height) * fraction
            )
        }
        origin.x += offset.width.isFinite ? offset.width : 0
        origin.y += offset.height.isFinite ? offset.height : 0
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }
}

// MARK: - Child Window Style
struct ChildWindowStyle {
    var background = AnyShapeStyle(.regularMaterial)
    var cornerRadius: CGFloat = 14
    var borderColor: Color = .primary.opacity(0.15)
    var borderWidth: CGFloat = 1
    var contentInsets = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
    var hasShadow = true
    var opacity: CGFloat = 1
}
