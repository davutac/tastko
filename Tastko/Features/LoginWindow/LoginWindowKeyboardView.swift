import CoreGraphics
import SwiftUI

// MARK: - LoginWindowKeyboardView
struct LoginWindowKeyboardView: View {
    static let headerHeight: CGFloat = 42
    let keyboard: LoginWindowKeyboard
    @Environment(\.keyboardService) private var keyboardService
    @Environment(\.keyboardLanguageService) private var languageService
    @Environment(\.keyboardPalette) private var palette

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("Tastko", systemImage: "keyboard")
                    .fontWeight(.semibold)
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(languageService.selectedLanguage?.shortTitle ?? "System") {
                    languageService.selectNextLanguage()
                }
                .help("Change keyboard language")
                .disabled(languageService.languages.count < 2)
            }
            .padding(.horizontal, 12)
            .frame(height: Self.headerHeight)
            PanelEditorLayoutView(panel: keyboard.panel)
                .padding(KeyboardDesign.Metrics.panelInset)
        }
        .background(palette.chassis)
        .clipShape(.rect(cornerRadius: KeyboardDesign.Metrics.windowRadius))
    }

    // MARK: - Status
    private var status: String {
        if let error = keyboardService.lastError { return error.localizedDescription }
        return CGPreflightPostEventAccess()
            ? "Login keyboard · predictions paused"
            : "macOS has not allowed keyboard input in this session"
    }
}
