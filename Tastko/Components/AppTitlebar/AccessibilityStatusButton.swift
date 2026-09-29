import SwiftUI

// MARK: - AccessibilityStatusButton
struct AccessibilityStatusButton: View {
    @Environment(\.accessibilityService) private var accessibilityService
    @Environment(\.keyboardPalette) private var palette

    // MARK: - Body
    var body: some View {
        Button("Accessibility Status", systemImage: "accessibility") {
            requestOrRefreshAuthorization()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .labelStyle(.iconOnly)
        .foregroundStyle(statusColor)
        .help(helpText)
        .onAppear {
            accessibilityService.refreshAuthorizationStatus()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            accessibilityService.refreshAuthorizationStatus()
        }
    }

    // MARK: - Authorization
    private func requestOrRefreshAuthorization() {
        if accessibilityService.isAuthorized {
            accessibilityService.refreshAuthorizationStatus()
        }
        else {
            accessibilityService.requestAuthorization()
        }
    }

    // MARK: - Status
    private var statusColor: Color {
        accessibilityService.isAuthorized
            ? palette.active : palette.error
    }

    private var accessibilityLabel: String {
        accessibilityService.isAuthorized
            ? "Accessibility access authorized"
            : "Accessibility access not authorized"
    }

    private var helpText: String {
        accessibilityService.isAuthorized
            ? "Accessibility access authorized"
            : "Accessibility access not authorized"
    }
}
