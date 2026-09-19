import SwiftUI

// MARK: - PanelEditorLayoutView
struct PanelEditorLayoutView: View {
    @Environment(\.keyboardLanguageService) private var keyboardLanguageService
    @Environment(\.keyboardService) private var keyboardService

    let panel: PanelEditorPanel

    // MARK: - Body
    var body: some View {
        GeometryReader { proxy in
            let bounds = panel.layoutBounds
            let scale = layoutScale(in: proxy.size)

            ZStack(alignment: .topLeading) {
                ForEach(panel.visibleButtons) { button in
                    PanelEditorButtonView(
                        button: button,
                        scale: scale,
                        languageContext: KeyboardLanguageContext(
                            language: keyboardLanguageService.selectedLanguage
                        )
                    )
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
            .frame(
                width: bounds.width * scale,
                height: bounds.height * scale,
                alignment: .topLeading
            )
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .onAppear {
            keyboardLanguageService.refreshSelectedLanguage()
        }
        .onDisappear { keyboardService.cancelKeyPresses() }
        .onChange(of: panel.id) { keyboardService.cancelKeyPresses() }
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
