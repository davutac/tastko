import AppKit
import Defaults
import SwiftUI

// MARK: - MainWindowContent
struct MainWindowContent: View {
    @Default(.selectedPanelEditorPanelID) private var selectedPanelIdentifier

    @Environment(\.keyboardService) private var keyboardService
    @Environment(\.floatingWindowController) private var floatingWindowController
    @Environment(\.panelEditorProfileStore) private var profileStore
    @Environment(\.windowDimensions) private var windowDimensions

    let presentationState: FloatingWindowPresentationState
    let minimumSize: CGSize
    let hide: () -> Void
    let minimize: () -> Void
    let expand: () -> Void

    // MARK: - Body
    var body: some View {
        Group {
            switch presentationState {
            case .expanded:
                expandedContent
            case .minimized:
                minimizedContent
            }
        }
        .foregroundStyle(KeyboardDesign.Palette.label)
        .background(KeyboardDesign.Palette.chassis)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(KeyboardDesign.Palette.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Expanded Content
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppTitlebar(
                close: hide,
                minimize: minimize
            ) {
                PanelEditorPanelPickerMenu(
                    profiles: profileStore.profiles,
                    selectedPanel: selectedPanel,
                    selectPanel: selectPanel,
                    reload: reloadProfilesAndWindow
                )
            }
            .zIndex(2)

            FunctionToolbarView(scale: functionToolbarScale)
                .frame(
                    height: PanelEditorWindowMetrics.functionToolbarBaseHeight
                        * functionToolbarScale
                )
                .frame(
                    height: PanelEditorWindowMetrics.functionToolbarBaseHeight
                        * functionToolbarScale * floatingWindowController.functionToolbarProgress,
                    alignment: .bottom
                )
                .clipped()
                .allowsHitTesting(floatingWindowController.functionToolbarProgress == 1)
                .accessibilityHidden(floatingWindowController.functionToolbarProgress < 1)

            KeyboardStatusView(
                profileError: selectedPanel == nil ? nil : profileStore.errorDescription,
                reloadProfiles: reloadProfilesAndWindow
            )
            .zIndex(1)

            panelContent
                .frame(maxWidth: .infinity)
                .frame(
                    height: selectedPanel.map {
                        $0.layoutBounds.height * functionToolbarScale
                            + PanelEditorWindowMetrics.panelPadding
                    }
                )
                .zIndex(0)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .onAppear {
            reloadProfiles()
        }
        .onChange(of: profileStore.panels.map(\.id)) {
            repairSelection()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            reloadProfiles()
        }
    }

    // MARK: - Panel Content
    private var functionToolbarScale: CGFloat {
        guard let selectedPanel else { return 1 }
        return PanelEditorWindowMetrics.keyboardScale(
            for: selectedPanel.layoutBounds.size,
            width: windowDimensions.size.width
        )
    }

    @ViewBuilder
    private var panelContent: some View {
        if let selectedPanel {
            PanelEditorLayoutView(panel: selectedPanel)
                .padding(KeyboardDesign.Metrics.panelInset)
        }
        else {
            ContentUnavailableView {
                Label("No Panel Editor Layout", systemImage: "rectangle.3.group")
            } description: {
                Text(
                    profileStore.errorDescription
                        ?? "Create a panel in macOS Panel Editor, then reload profiles."
                )
            } actions: {
                Button("Reload", systemImage: "arrow.clockwise") {
                    reloadProfilesAndWindow()
                }
            }
        }
    }

    // MARK: - Minimized Content
    private var minimizedContent: some View {
        GeometryReader { proxy in
            let buttonSize = CGSize(
                width: max(FloatingWindowDefaults.miniButtonSideLength, proxy.size.width),
                height: max(FloatingWindowDefaults.miniButtonSideLength, proxy.size.height)
            )

            ZStack {
                Button(action: expand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(
                    .scaledIcon(
                        size: buttonSize,
                        symbolScaleFactor: 0.46
                    )
                )
                .accessibilityLabel("Expand")
                .help("Expand")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(FloatingWindowDefaults.miniContentPadding)
        .frame(
            minWidth: minimumSize.width,
            maxWidth: .infinity,
            minHeight: minimumSize.height,
            maxHeight: .infinity
        )
    }

    // MARK: - Styling
    private var cornerRadius: CGFloat {
        switch presentationState {
        case .expanded:
            KeyboardDesign.Metrics.windowRadius
        case .minimized:
            14
        }
    }

    // MARK: - Selection
    private var selectedPanel: PanelEditorPanel? {
        guard
            let selectedPanelIdentifier,
            let selectedPanel = profileStore.panels.first(where: {
                $0.id == selectedPanelIdentifier
            })
        else {
            return profileStore.panels.first
        }

        return selectedPanel
    }

    private func selectPanel(_ panel: PanelEditorPanel) {
        keyboardService.releaseAllModifiers()
        selectedPanelIdentifier = panel.id
        floatingWindowController.updateSettings()
    }

    private func repairSelection() {
        guard let selectedPanel else {
            selectedPanelIdentifier = nil
            return
        }

        selectedPanelIdentifier = selectedPanel.id
    }

    private func reloadProfiles() {
        profileStore.reload()
        repairSelection()
    }

    private func reloadProfilesAndWindow() {
        reloadProfiles()
        floatingWindowController.updateSettings()
    }
}
