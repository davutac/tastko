import AppKit
import Defaults
import OSLog
import Observation
import SwiftUI

// MARK: - FloatingWindowPresentationState
enum FloatingWindowPresentationState: Equatable {
    case expanded
    case minimized
}

// MARK: - FloatingWindowController
@Observable
@MainActor
final class FloatingWindowController {
    static let shared = FloatingWindowController()
    var sentenceService: SentenceCompletionService?

    private let floatingWindowManager = FloatingWindowManager.shared

    private init() {}

    private(set) var presentationState: FloatingWindowPresentationState = .expanded
    private(set) var isHiddenForInactivity = false
    private(set) var isFunctionToolbarVisible = Defaults[.functionToolbarVisible]
    private(set) var functionToolbarProgress: CGFloat = Defaults[.functionToolbarVisible] ? 1 : 0
    @ObservationIgnored private var toolbarAnchor: CGPoint?
    @ObservationIgnored private var lastToolbarOrigin: CGPoint?
    private(set) var isScreenLocked = false
    private(set) var lockScreenDisplayStatus = "Disabled"
    @ObservationIgnored private var presentationBeforeLock:
        (
            visible: Bool, inactive: Bool, presentation: FloatingWindowPresentationState
        )?

    var isVisible: Bool {
        floatingWindowManager.isVisible(.main)
    }

    // MARK: - Actions
    func toggle() {
        guard !isScreenLocked else { return }
        if isVisible {
            hide()
        }
        else {
            show()
        }
    }

    func show(preservingCurrentOrigin: Bool = false) {
        PhysicalKeyboardState.shared.refresh()
        isHiddenForInactivity = false
        finishToolbarAnimation()
        let presentationState = presentationState
        let configuration = configuration(for: presentationState)

        floatingWindowManager.show(
            .main,
            configuration: configuration,
            preservingCurrentOrigin: preservingCurrentOrigin
        ) { [weak self] _ in
            MainWindowContent(
                presentationState: presentationState,
                minimumSize: configuration.minSize,
                hide: { self?.hide() },
                minimize: { self?.minimize() },
                expand: { self?.expand() }
            )
        }
        if presentationState == .expanded && !isScreenLocked,
            let sentenceService,
            sentenceService.isGenerating || !sentenceService.suggestions.isEmpty
                || sentenceService.error != nil
        {
            floatingWindowManager.showChild(
                .keyboardCompanion,
                attachedTo: .main,
                configuration: .keyboardCompanion
            ) {
                KeyboardCompanionView()
            }
        }
        else {
            floatingWindowManager.hideChild(.keyboardCompanion, attachedTo: .main)
        }
        updatePredictionLifecycle()
    }

    func hide() {
        guard !isScreenLocked else { return }
        KeyboardService.shared.releaseAllModifiers()
        finishToolbarAnimation()
        isHiddenForInactivity = false
        TextPredictionService.shared.stop()
        floatingWindowManager.hide(.main)
    }

    // MARK: - Pointer Visibility
    func handlePointerVisibility(_ action: PointerVisibilityAction) {
        guard !isScreenLocked else { return }
        switch action {
        case .toggle:
            toggle()
        case .hideForInactivity:
            guard isVisible else { return }
            hide()
            isHiddenForInactivity = true
        case .restoreFromInactivity:
            guard isHiddenForInactivity else { return }
            show()
        }
    }

    // MARK: - Presentation
    func screenLockDidChange(_ locked: Bool) {
        guard isScreenLocked != locked else { return }
        isScreenLocked = locked
        KeyboardService.shared.setScreenLocked(
            locked,
            allowsInput: locked && Defaults[.experimentalLockScreenDisplay]
        )
        if locked {
            presentationBeforeLock = (isVisible, isHiddenForInactivity, presentationState)
            TextPredictionService.shared.stop()
            if Defaults[.experimentalLockScreenDisplay] {
                let wasExpanded = presentationState == .expanded
                presentationState = .expanded
                show(preservingCurrentOrigin: wasExpanded)
                floatingWindowManager.setPreventsHiding(true, for: .main)
                updateLockScreenDisplay()
            }
        }
        else {
            floatingWindowManager.setPreventsHiding(false, for: .main)
            try? floatingWindowManager.setLockScreenDisplay(false, for: .main)
            if let previous = presentationBeforeLock {
                presentationBeforeLock = nil
                presentationState = previous.presentation
                if previous.visible {
                    show(preservingCurrentOrigin: previous.presentation == .expanded)
                }
                else {
                    hide()
                }
                isHiddenForInactivity = previous.inactive
            }
            updatePredictionLifecycle()
            lockScreenDisplayStatus =
                Defaults[.experimentalLockScreenDisplay]
                ? "Ready for a manual lock test" : "Disabled"
        }
    }

    func updateLockScreenDisplay() {
        let enabled = Defaults[.experimentalLockScreenDisplay]
        KeyboardService.shared.setScreenLocked(
            isScreenLocked,
            allowsInput: isScreenLocked && enabled
        )
        do {
            // Validate attachment and restoration now, before the user's manual lock.
            try floatingWindowManager.setLockScreenDisplay(enabled, for: .main)
            if !isScreenLocked {
                try floatingWindowManager.setLockScreenDisplay(false, for: .main)
            }
            lockScreenDisplayStatus =
                enabled
                ? (isScreenLocked
                    ? "Private display configured; input acceptance unverified"
                    : "Ready for a manual lock test")
                : "Disabled"
            Logger(subsystem: "com.davutcaliskan.Tastko", category: "LockScreenDisplay")
                .notice("\(self.lockScreenDisplayStatus, privacy: .public)")
        }
        catch {
            lockScreenDisplayStatus = "Unavailable: \(error)"
            Logger(subsystem: "com.davutcaliskan.Tastko", category: "LockScreenDisplay")
                .error("\(self.lockScreenDisplayStatus, privacy: .public)")
        }
    }

    func stopLockScreenDisplay() {
        floatingWindowManager.setPreventsHiding(false, for: .main)
        try? floatingWindowManager.setLockScreenDisplay(false, for: .main)
    }

    func minimize() {
        guard !isScreenLocked else { return }
        KeyboardService.shared.releaseAllModifiers()
        finishToolbarAnimation()
        presentationState = .minimized
        show()
    }

    func expand() {
        presentationState = .expanded
        show()
    }

    func updateSettings() {
        guard isVisible else { return }

        show(preservingCurrentOrigin: true)
    }

    // MARK: - Function Toolbar
    func toggleFunctionToolbar() {
        isFunctionToolbarVisible.toggle()
        Defaults[.functionToolbarVisible] = isFunctionToolbarVisible
        let target: CGFloat = isFunctionToolbarVisible ? 1 : 0
        guard isVisible, presentationState == .expanded else {
            functionToolbarProgress = target
            return
        }

        let initialProgress = functionToolbarProgress
        let frame = floatingWindowManager.frame(.main)
        var configuration = expandedConfiguration(functionToolbarProgress: target)
        if let frame {
            if lastToolbarOrigin != frame.origin { toolbarAnchor = frame.origin }
            let anchor = toolbarAnchor ?? frame.origin
            configuration.size.width = frame.width
            configuration.size.height =
                configuration.contentHeightForWidth?(frame.width)
                ?? configuration.size.height
            configuration.origin = anchor
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) {
                configuration.origin = PanelEditorWindowMetrics.fittedOrigin(
                    anchor,
                    size: configuration.size,
                    in: screen.visibleFrame
                )
            }
        }
        floatingWindowManager.animateGeometry(
            .main,
            configuration: configuration,
            duration: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? 0 : 0.2 * abs(target - initialProgress)
        ) { [weak self] fraction in
            guard let self else { return }
            self.functionToolbarProgress = initialProgress + (target - initialProgress) * fraction
            self.lastToolbarOrigin = self.floatingWindowManager.frame(.main)?.origin
        }
    }

    private func finishToolbarAnimation() {
        toolbarAnchor = nil
        lastToolbarOrigin = nil
        functionToolbarProgress = isFunctionToolbarVisible ? 1 : 0
    }

    // MARK: - Predictions
    func updatePredictionLifecycle() {
        if !isScreenLocked, isVisible, presentationState == .expanded,
            Defaults[.textPredictionEnabled]
        {
            TextPredictionService.shared.start()
        }
        else {
            TextPredictionService.shared.stop()
        }
    }

    // MARK: - Active Application
    func applicationDidActivate(_ application: NSRunningApplication) {
        guard !isScreenLocked else { return }
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }

        let panel = PanelEditorProfileStore.preferredPanel(
            in: PanelEditorProfileStore.shared.profiles,
            forApplicationBundleIdentifier: application.bundleIdentifier,
            currentPanelIdentifier: Defaults[.selectedPanelEditorPanelID]
        )

        guard
            let panel,
            panel.id != Defaults[.selectedPanelEditorPanelID]
        else {
            return
        }

        KeyboardService.shared.cancelKeyPresses()
        Defaults[.selectedPanelEditorPanelID] = panel.id
        updateSettings()
    }

    // MARK: - Configuration
    private func configuration(
        for presentationState: FloatingWindowPresentationState
    ) -> AlwaysOnTopWindowConfiguration {
        switch presentationState {
        case .expanded:
            expandedConfiguration()
        case .minimized:
            minimizedConfiguration()
        }
    }

    private func expandedConfiguration(functionToolbarProgress: CGFloat? = nil)
        -> AlwaysOnTopWindowConfiguration
    {
        var configuration = PanelEditorWindowMetrics.expandedConfiguration(
            size: FloatingWindowDefaults.size,
            origin: FloatingWindowDefaults.origin,
            minimumScale: FloatingWindowDefaults.minimumKeyboardScale,
            panelSize: selectedPanel?.layoutBounds.size,
            functionToolbarProgress: functionToolbarProgress ?? self.functionToolbarProgress
        )
        configuration.sizeDidChange = { size in
            Defaults[.floatingWindowSize] = StoredWindowSize(size)
        }
        configuration.originDidChange = { origin in
            Defaults[.floatingWindowOrigin] = StoredWindowOrigin(origin)
        }
        return configuration
    }

    private var selectedPanel: PanelEditorPanel? {
        let panels = PanelEditorProfileStore.shared.panels
        let selectedPanelID = Defaults[.selectedPanelEditorPanelID]
        return panels.first { $0.id == selectedPanelID } ?? panels.first
    }

    // MARK: - Minimized Configuration
    private func minimizedConfiguration() -> AlwaysOnTopWindowConfiguration {
        AlwaysOnTopWindowConfiguration(
            size: FloatingWindowDefaults.miniSize,
            minSize: FloatingWindowDefaults.minimumMiniSize,
            maxSize: FloatingWindowDefaults.maximumMiniSize,
            origin: FloatingWindowDefaults.miniOrigin,
            contentAspectRatio: CGSize(width: 1, height: 1),
            storageKey: "mainMini",
            sizeDidChange: { size in
                Defaults[.floatingWindowMiniSize] = StoredWindowSize(
                    FloatingWindowDefaults.sanitizedMiniSize(size)
                )
            },
            originDidChange: { origin in
                Defaults[.floatingWindowMiniOrigin] = StoredWindowOrigin(origin)
            }
        )
    }
}
