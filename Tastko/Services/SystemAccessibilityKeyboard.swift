import AppKit
import ApplicationServices

// MARK: - SystemAccessibilityKeyboard
@MainActor
enum SystemAccessibilityKeyboard {
    private static let settingsBundleIdentifier = "com.apple.systempreferences"
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.universalaccess?Keyboard"
    )!

    // MARK: - Toggle
    static func toggle() async throws {
        guard AXIsProcessTrusted() else {
            throw AccessibilityFocusError.accessibilityNotAuthorized
        }

        let workspace = NSWorkspace.shared
        let previousApplication = workspace.frontmostApplication
        let existingSettings = NSRunningApplication.runningApplications(
            withBundleIdentifier: settingsBundleIdentifier
        ).first
        let hideSettingsAfterward = existingSettings?.isHidden ?? true
        guard
            let applicationURL = workspace.urlForApplication(
                withBundleIdentifier: settingsBundleIdentifier
            )
        else { throw ToggleError.couldNotToggle }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = hideSettingsAfterward
        let settings = try await workspace.open(
            [settingsURL],
            withApplicationAt: applicationURL,
            configuration: configuration
        )
        defer {
            if hideSettingsAfterward { settings.hide() }
            if workspace.frontmostApplication?.bundleIdentifier == settingsBundleIdentifier,
                previousApplication?.bundleIdentifier != settingsBundleIdentifier
            {
                previousApplication?.activate()
            }
        }

        let application = AXUIElementCreateApplication(settings.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.2)
        var requestedState: Bool?
        var confirmedDisable = false
        let deadline = ContinuousClock.now + .seconds(8)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if requestedState != nil {
                try await Task.sleep(for: .milliseconds(200))
            }
            if let sheet = element(
                in: application,
                attribute: kAXRoleAttribute,
                matching: kAXSheetRole
            ) {
                // Only accept the confirmation produced by our own off action.
                guard requestedState == false else { throw ToggleError.couldNotToggle }
                if !confirmedDisable,
                    let confirm = element(
                        in: sheet,
                        attribute: kAXIdentifierAttribute,
                        matching: "action-button-1"
                    )
                {
                    try press(confirm)
                    confirmedDisable = true
                }
                continue
            }

            guard
                let toggle = element(
                    in: application,
                    attribute: kAXIdentifierAttribute,
                    matching: "AX_VIRTUAL_KEYBOARD"
                ), let value = attribute(kAXValueAttribute, of: toggle) as? NSNumber
            else {
                try await Task.sleep(for: .milliseconds(200))
                continue
            }

            if let requestedState {
                if value.boolValue == requestedState { return }
            }
            else {
                requestedState = !value.boolValue
                try press(toggle)
            }
        }
        throw ToggleError.couldNotToggle
    }

    // MARK: - Settings
    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }

    // MARK: - Find Settings Control
    private static func element(
        in application: AXUIElement,
        attribute name: String,
        matching expectedValue: String
    ) -> AXUIElement? {
        var pending = [application]
        var remaining = 500
        while let element = pending.popLast(), remaining > 0 {
            remaining -= 1
            if attribute(name, of: element) as? String == expectedValue {
                return element
            }
            if let children = attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] {
                pending.append(contentsOf: children)
            }
        }
        return nil
    }

    // MARK: - Press Settings Control
    private static func press(_ element: AXUIElement) throws {
        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
        else { throw ToggleError.couldNotToggle }
    }

    // MARK: - Read Accessibility Attribute
    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        else { return nil }
        return value
    }

    // MARK: - Toggle Error
    private enum ToggleError: LocalizedError {
        case couldNotToggle

        var errorDescription: String? {
            "Toggle Accessibility Keyboard in System Settings → Accessibility → Keyboard."
        }
    }
}
