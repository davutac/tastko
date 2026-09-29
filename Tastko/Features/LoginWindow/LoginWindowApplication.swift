import AppKit
import CoreGraphics
import OSLog
import SwiftUI

// MARK: - LoginWindowSession
enum LoginWindowSession {
    // MARK: - Session State
    static var isActive: Bool {
        allowsInput(userID: getuid(), loginDone: loginDone)
    }

    static var loginDone: Bool? {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?[kCGSessionLoginDoneKey as String] as? Bool
    }

    static func allowsInput(userID: uid_t, loginDone: Bool?) -> Bool {
        userID == 0 && loginDone == false
    }
}

// MARK: - LoginWindowApplication
@MainActor
final class LoginWindowApplication: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.davutcaliskan.Tastko", category: "LoginWindow")
    private var panel: AlwaysOnTopPanel?
    private var sessionTimer: Timer?
    private var terminationSignal: (any DispatchSourceSignal)?

    // MARK: - Startup
    static func run() {
        guard getuid() == 0 else { return }
        // launchd retries if the WindowServer session is not ready yet.
        guard let loginDone = LoginWindowSession.loginDone else { exit(EX_TEMPFAIL) }
        guard !loginDone else { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = LoginWindowApplication()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            guard let url = Bundle.main.url(forResource: "LoginKeyboard", withExtension: "json")
            else { throw CocoaError(.fileNoSuchFile) }
            let keyboard = try LoginWindowKeyboard.load(from: url)
            KeyboardService.shared.setScreenLocked(true, allowsInput: true)
            PhysicalKeyboardState.shared.start()
            try show(keyboard)
            observeSessionEnd()
            logger.notice(
                "Login keyboard shown; event posting permission: \(CGPreflightPostEventAccess())"
            )
        }
        catch {
            logger.error(
                "Login keyboard could not start: \(error.localizedDescription, privacy: .public)"
            )
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Keyboard Window
    private func show(_ keyboard: LoginWindowKeyboard) throws {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            throw CocoaError(.featureUnsupported)
        }
        let bounds = screen.visibleFrame.insetBy(dx: 20, dy: 20)
        let layoutSize = keyboard.panel.layoutBounds.size
        let padding = PanelEditorWindowMetrics.panelPadding
        let width = min(
            keyboard.width,
            bounds.width,
            (bounds.height - LoginWindowKeyboardView.headerHeight - padding) * layoutSize.width
                / layoutSize.height + padding
        )
        let size = CGSize(
            width: width,
            height: PanelEditorWindowMetrics.keyboardScale(for: layoutSize, width: width)
                * layoutSize.height + padding + LoginWindowKeyboardView.headerHeight
        )
        let panel = AlwaysOnTopPanel(
            configuration: .init(
                size: size,
                minSize: size,
                maxSize: size,
                origin: CGPoint(x: bounds.midX - width / 2, y: bounds.minY),
                level: .screenSaver,
                allowsResizing: false
            )
        )
        panel.title = "Tastko"
        panel.canBecomeVisibleWithoutLogin = true
        panel.preventsHiding = true
        let host = NSHostingView(rootView: LoginWindowKeyboardView(keyboard: keyboard).keyboardTheme())
        host.sizingOptions = []
        host.safeAreaRegions = []
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel
    }

    // MARK: - Handoff
    private func observeSessionEnd() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApplication.shared.terminate(nil) }
        source.resume()
        terminationSignal = source
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                if !LoginWindowSession.isActive { NSApplication.shared.terminate(nil) }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        PhysicalKeyboardState.shared.stop()
        KeyboardService.shared.setScreenLocked(true, allowsInput: false)
        sessionTimer?.invalidate()
        terminationSignal?.cancel()
        panel?.preventsHiding = false
        panel?.close()
        logger.notice("Login keyboard stopped; the user's login item handles normal startup")
    }
}
