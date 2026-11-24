import SwiftUI

// MARK: - PanelEditorLayoutView
struct PanelEditorLayoutView: View {
    @Environment(\.keyboardLanguageService) private var keyboardLanguageService
    @Environment(\.keyboardService) private var keyboardService
    @Environment(\.swipeTypingController) private var swipeTyping

    let panel: PanelEditorPanel
    /// Whether a letter press may become a swipe. The login window keyboard turns it off.
    var allowsSwipeTyping = true

    // MARK: - Body
    var body: some View {
        GeometryReader { proxy in
            let bounds = panel.layoutBounds
            let scale = layoutScale(in: proxy.size)

            // Lets Glass-style keys share one backdrop pass instead of sampling it per key.
            GlassEffectContainer(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    ForEach(panel.visibleButtons) { button in
                        PanelEditorButtonView(button: button, scale: scale)
                            .frame(
                                width: button.frame.width * scale,
                                height: button.frame.height * scale
                            )
                            .offset(
                                x: (button.frame.minX - bounds.minX) * scale,
                                y: (button.frame.minY - bounds.minY) * scale
                            )
                    }
                }
            }
            .frame(
                width: bounds.width * scale,
                height: bounds.height * scale,
                alignment: .topLeading
            )
            .overlay(alignment: .topLeading) {
                SwipeTrailView(controller: swipeTyping, origin: bounds.origin, scale: scale)
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .onAppear {
            keyboardLanguageService.refreshSelectedLanguage()
        }
        .onDisappear {
            keyboardService.cancelPresses()
            swipeTyping.configure(panel: nil)
        }
        .onChange(of: panel.id) { keyboardService.cancelPresses() }
        .onChange(
            of: SwipeTypingConfiguration(panel: panel, allowed: allowsSwipeTyping),
            initial: true
        ) {
            swipeTyping.configure(panel: allowsSwipeTyping ? panel : nil)
        }
        .onChange(of: keyboardLanguageService.selectedLanguageID) {
            swipeTyping.configure(panel: allowsSwipeTyping ? panel : nil)
        }
    }

    // MARK: - Metrics
    private func layoutScale(in availableSize: CGSize) -> CGFloat {
        let size = panel.layoutBounds.size
        guard
            availableSize.width.isFinite,
            availableSize.height.isFinite,
            availableSize.width > 0,
            availableSize.height > 0,
            size.width > 0,
            size.height > 0
        else {
            return 1
        }

        return min(
            availableSize.width / size.width,
            availableSize.height / size.height
        )
    }
}

// MARK: - SwipeTypingConfiguration
/// What swipe typing is prepared for: the shown panel, where swipes may start.
private struct SwipeTypingConfiguration: Equatable {
    let panel: PanelEditorPanel
    let allowed: Bool
}
