import AppKit
import SwiftUI

// MARK: - Settings Window Configuration
struct SettingsWindowConfiguration: NSViewRepresentable {
    // MARK: - View Creation
    func makeNSView(context: Context) -> WindowView { WindowView() }

    // MARK: - View Update
    func updateNSView(_ nsView: WindowView, context: Context) {}

    // MARK: - Window Attachment
    final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Settings applies its preference toolbar after attaching the content; the
            // sidebar layout needs the unified style instead.
            DispatchQueue.main.async { [weak window] in
                window?.toolbarStyle = .unified
            }
        }
    }
}
