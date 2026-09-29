import SwiftUI

// MARK: - Settings View
@MainActor
struct SettingsView: View {
    let updateService: AppUpdateService
    let aiService: AIProviderService
    @SceneStorage("settings.pane") private var selection = SettingsPane.general

    // MARK: - Body
    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: sidebarSelection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    SettingsPaneIcon(pane: pane)
                }
                .tag(pane)
            }
            .accessibilityIdentifier("settings.sidebar")
            .navigationSplitViewColumnWidth(200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(selection.title)
        }
        .background(SettingsWindowConfiguration())
        .frame(width: 820, height: 640)
    }

    // MARK: - Detail
    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general:
            GeneralSettingsView(updateService: updateService)
        case .appearance:
            AppearanceSettingsView()
        case .typing:
            TypingSettingsView()
        case .ai:
            AIProviderSettingsView(service: aiService)
        case .advanced:
            AdvancedSettingsView()
        #if DEBUG
            case .debug:
                AIDebugView(service: aiService)
        #endif
        }
    }

    // MARK: - Selection
    /// The sidebar can deselect its row; keep the current pane when it does.
    private var sidebarSelection: Binding<SettingsPane?> {
        Binding {
            selection
        } set: { newValue in
            if let newValue { selection = newValue }
        }
    }
}

#Preview {
    SettingsView(
        updateService: AppUpdateService(),
        aiService: AIProviderService(persistence: AppPersistence(inMemory: true))
    )
}
