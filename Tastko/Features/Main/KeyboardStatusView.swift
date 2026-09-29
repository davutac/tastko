import SwiftUI

// MARK: - KeyboardStatusView
struct KeyboardStatusView: View {
    @Environment(\.accessibilityService) private var accessibilityService
    @Environment(\.keyboardService) private var keyboardService
    @Environment(\.textPredictionService) private var textPredictionService
    @Environment(\.floatingWindowController) private var floatingWindowController
    @Environment(\.keyboardPalette) private var palette

    let profileError: String?
    let reloadProfiles: () -> Void

    @State private var showsProfileError = false

    // MARK: - Body
    var body: some View {
        HStack(spacing: KeyboardDesign.Metrics.rowSpacing) {
            statusContent
                .frame(maxWidth: .infinity, alignment: .leading)
            KeyboardLanguageCycleButton()
                .buttonStyle(.keycap)
                .fixedSize()
            FunctionToolbarToggleButton()
                .buttonStyle(.keycap)
                .fixedSize()
        }
        .font(KeyboardDesign.Typography.toolbar)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(
            .horizontal,
            KeyboardDesign.Metrics.panelInset + KeyboardDesign.Metrics.keyInset
        )
        .padding(.top, KeyboardDesign.Metrics.suggestionTopInset)
        .padding(.bottom, KeyboardDesign.Metrics.suggestionBottomInset)
        .frame(height: PanelEditorWindowMetrics.statusBarHeight)
    }

    // MARK: - Status Content
    private var statusContent: some View {
        HStack(spacing: KeyboardDesign.Metrics.rowSpacing) {
            if floatingWindowController.isScreenLocked {
                Label(
                    keyboardService.lastError?.localizedDescription
                        ?? "Lock-screen keyboard · predictions paused",
                    systemImage: "lock"
                )
            }
            else if !accessibilityService.isAuthorized {
                Label("Allow Accessibility access to type", systemImage: "accessibility")
                Spacer(minLength: 0)
                Button("Allow Access") {
                    accessibilityService.requestAuthorization()
                }
                .buttonStyle(.keycap)
            }
            else if let profileError {
                Label("Some profiles could not be loaded", systemImage: "exclamationmark.triangle")
                Spacer(minLength: 0)
                Button("Details") {
                    showsProfileError = true
                }
                .popover(isPresented: $showsProfileError) {
                    ScrollView {
                        Text(profileError)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(width: 360, height: 180)
                }
                Button("Reload", action: reloadProfiles)
            }
            else if let error = keyboardService.lastError {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .help(error.localizedDescription)
            }
            else if textPredictionService.hasTextContext {
                WordSuggestionsView(service: textPredictionService)
            }
            else {
                Text("Select an input in another app and start typing.")
                    .foregroundStyle(palette.secondaryLabel)
            }
        }
    }
}
