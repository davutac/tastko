import SwiftUI

// MARK: - EnvironmentValues
extension EnvironmentValues {
    @Entry var appUpdateService: AppUpdateService = .shared
    @Entry var accessibilityService: AccessibilityService = .shared
    @Entry var floatingWindowController: FloatingWindowController = .shared
    @Entry var floatingWindowManager: FloatingWindowManager = .shared
    @Entry var keyboardService: KeyboardService = .shared
    @Entry var keyInputController: KeyInputController = .shared
    @Entry var textPredictionService: TextPredictionService = .shared
    @Entry var keyboardLanguageService: KeyboardLanguageService = .shared
    @Entry var panelEditorProfileStore: PanelEditorProfileStore = .shared
    @Entry var soundService: SoundService = .shared
    @Entry var windowDimensions: WindowDimensions = .environmentDefault
}
