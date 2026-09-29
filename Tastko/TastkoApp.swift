import AppKit
import SwiftUI

struct TastkoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openSettings) private var openSettings

    // MARK: - Body
    var body: some Scene {
        MenuBarExtra("Tastko", systemImage: "keyboard") {
            menuItems
        }

        Settings {
            SettingsView(updateService: appDelegate.updateService, aiService: appDelegate.aiService)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…", action: appDelegate.updateService.checkForUpdates)
                    .disabled(!appDelegate.updateService.canCheckForUpdates)
            }
        }
    }

    // MARK: - Menu
    @ViewBuilder
    private var menuItems: some View {
        Button(appDelegate.isFloatingWindowVisible ? "Hide Window" : "Show Window") {
            appDelegate.toggleFloatingWindow()
        }
        .disabled(appDelegate.floatingWindowController.isScreenLocked)

        Button(
            appDelegate.isKeyboardDebugWindowVisible ? "Hide Keyboard Debug" : "Show Keyboard Debug"
        ) {
            appDelegate.toggleKeyboardDebugWindow()
        }

        Divider()

        Button("Settings…") {
            openSettings()
            NSApplication.shared.activate()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Check for Updates…", action: appDelegate.updateService.checkForUpdates)
            .disabled(!appDelegate.updateService.canCheckForUpdates)

        Divider()

        Button("Quit Tastko") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
