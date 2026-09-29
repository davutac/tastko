import AppKit
import SwiftUI

// MARK: - HotCornerIndicatorController
@MainActor
final class HotCornerIndicatorController {
    private var panel: HotCornerIndicatorPanel?
    private var hostingView: NSHostingView<HotCornerProgressView>?

    // MARK: - Progress
    func update(_ progress: HotCornerProgress?) {
        guard let progress else {
            if panel?.isVisible == true { panel?.orderOut(nil) }
            return
        }

        let panel = panel ?? makePanel(progress: progress)
        let size = panel.frame.size
        let origin = CGPoint(
            x: progress.screenFrame.maxX - size.width - 12,
            y: progress.screenFrame.minY + 12
        )
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        hostingView?.rootView = HotCornerProgressView(progress: progress)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    // MARK: - Panel
    private func makePanel(progress: HotCornerProgress) -> HotCornerIndicatorPanel {
        let panel = HotCornerIndicatorPanel()
        let hostingView = NSHostingView(rootView: HotCornerProgressView(progress: progress))
        panel.contentView = hostingView
        self.hostingView = hostingView
        self.panel = panel
        return panel
    }
}

// MARK: - HotCornerIndicatorPanel
final class HotCornerIndicatorPanel: NSPanel {
    // MARK: - Initialization
    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 60, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - HotCornerProgressView
private struct HotCornerProgressView: View {
    let progress: HotCornerProgress

    // MARK: - Body
    var body: some View {
        HotCornerProgressRing(progress: progress)
            .keyboardTheme()
    }
}

// MARK: - HotCornerProgressRing
private struct HotCornerProgressRing: View {
    let progress: HotCornerProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.keyboardPalette) private var palette

    // MARK: - Body
    var body: some View {
        ZStack {
            Circle().fill(palette.chassis)
            Circle().stroke(palette.border, lineWidth: 1)
            Circle()
                .trim(from: 0, to: progress.fraction)
                .stroke(
                    palette.active,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(5)
                .animation(reduceMotion ? nil : .linear(duration: 0.1), value: progress.fraction)
            Text("\(progress.remaining, format: .number.precision(.fractionLength(1)))s")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(palette.label)
        }
        .padding(1)
        .frame(width: 60, height: 60)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
