import AppKit
import ApplicationServices
import Observation

// MARK: - AccessibilityFocusRoute
nonisolated enum AccessibilityFocusRoute: Hashable, Sendable {
    case textElement
    case window
    case application
}

// MARK: - FocusedKeyboardTarget
struct FocusedKeyboardTarget {
    let processIdentifier: pid_t
    let applicationName: String?
    let applicationElement: AXUIElement
    let focusedTextElement: AXUIElement?
    let focusedWindow: AXUIElement?
    let route: AccessibilityFocusRoute
    var focusedElement: AXUIElement? = nil

    var targetElement: AXUIElement {
        switch route {
        case .textElement:
            focusedTextElement ?? applicationElement
        case .window:
            focusedWindow ?? applicationElement
        case .application:
            applicationElement
        }
    }

    // MARK: - Target Identity
    func hasSameElement(as other: FocusedKeyboardTarget) -> Bool {
        processIdentifier == other.processIdentifier && CFEqual(targetElement, other.targetElement)
    }

    // MARK: - Complete Focus Identity
    func hasSameFocus(as other: FocusedKeyboardTarget) -> Bool {
        guard hasSameElement(as: other),
            CFEqual(focusedElement ?? targetElement, other.focusedElement ?? other.targetElement)
        else { return false }
        switch (focusedWindow, other.focusedWindow) {
        case (nil, nil): return true
        case (let lhs?, let rhs?): return CFEqual(lhs, rhs)
        default: return false
        }
    }
}

// MARK: - KeyboardTargetDebugSnapshot
nonisolated struct KeyboardTargetDebugSnapshot: Hashable, Sendable {
    let capturedAt: Date
    let isAuthorized: Bool
    let canSendKeystrokes: Bool
    let hasFocusedTextInput: Bool
    let route: AccessibilityFocusRoute?
    let processIdentifier: pid_t?
    let applicationName: String?
    let focusedWindow: AccessibilityElementDebugInfo?
    let focusedElement: AccessibilityElementDebugInfo?
    let focusedText: FocusedTextValue?
    let errorDescription: String?

    static var unchecked: KeyboardTargetDebugSnapshot {
        KeyboardTargetDebugSnapshot(
            capturedAt: .now,
            isAuthorized: false,
            canSendKeystrokes: false,
            hasFocusedTextInput: false,
            route: nil,
            processIdentifier: nil,
            applicationName: nil,
            focusedWindow: nil,
            focusedElement: nil,
            focusedText: nil,
            errorDescription: "Not checked"
        )
    }
}

// MARK: - AccessibilityElementDebugInfo
nonisolated struct AccessibilityElementDebugInfo: Hashable, Sendable {
    let role: String?
    let subrole: String?
    let roleDescription: String?
    let title: String?
    let isSecureTextInput: Bool
}

// MARK: - FocusedTextValue
nonisolated struct FocusedTextValue: Hashable, Sendable {
    let text: String?
    let selectedText: String?
    let selectedRange: AccessibilityTextRange?
    let numberOfCharacters: Int?

    var cursorLocation: Int? {
        selectedRange?.location
    }

    // MARK: - Cursor Context
    func textBeforeCursor(limit: Int? = nil) -> String? {
        guard let text, let cursorLocation else {
            return nil
        }

        let nsText = text as NSString
        let clampedCursor = min(max(cursorLocation, 0), nsText.length)
        let start = limit.map { max(clampedCursor - $0, 0) } ?? 0
        var value = nsText.substring(with: NSRange(location: start, length: clampedCursor - start))

        if start > 0 {
            value = "..." + value
        }

        return value
    }

    func textAfterCursor(limit: Int? = nil) -> String? {
        guard let text, let cursorLocation else {
            return nil
        }

        let nsText = text as NSString
        let clampedCursor = min(max(cursorLocation, 0), nsText.length)
        let end = limit.map { min(clampedCursor + $0, nsText.length) } ?? nsText.length
        var value = nsText.substring(
            with: NSRange(location: clampedCursor, length: end - clampedCursor)
        )

        if end < nsText.length {
            value += "..."
        }

        return value
    }

    func textAroundCursor(limit: Int = 80) -> String? {
        guard let text, !text.isEmpty else {
            return text
        }

        let nsText = text as NSString
        let length = nsText.length
        let cursorLocation = min(max(cursorLocation ?? length, 0), length)
        let start = max(cursorLocation - limit, 0)
        let end = min(cursorLocation + limit, length)
        var preview = nsText.substring(with: NSRange(location: start, length: end - start))

        if start > 0 {
            preview = "..." + preview
        }

        if end < length {
            preview += "..."
        }

        return preview
    }
}

// MARK: - FocusedKeyboardContext
private struct FocusedKeyboardContext {
    let processIdentifier: pid_t
    let applicationName: String?
    let applicationElement: AXUIElement
    let focusedElement: AXUIElement?
    let focusedWindow: AXUIElement?
}

// MARK: - AccessibilityFocusError
nonisolated enum AccessibilityFocusError: Equatable, LocalizedError, Sendable {
    case accessibilityNotAuthorized
    case focusedApplicationUnavailable
    case focusedApplicationPIDUnavailable(AXError)
    case secureTextInput
    case attributeUnavailable(String, AXError)
    case invalidAttributeValue(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityNotAuthorized:
            "Accessibility access is not authorized."
        case .focusedApplicationUnavailable:
            "A focused application could not be resolved."
        case .focusedApplicationPIDUnavailable:
            "The focused application's process identifier could not be resolved."
        case .secureTextInput:
            "The focused input is secure text input."
        case .attributeUnavailable(let attribute, let error):
            "Accessibility attribute \(attribute) is unavailable: \(error)."
        case .invalidAttributeValue(let attribute):
            "Accessibility attribute \(attribute) has an unexpected value."
        }
    }
}

// MARK: - AccessibilityService
@Observable
@MainActor
final class AccessibilityService {
    static let shared = AccessibilityService()

    private(set) var isAuthorized = false

    /// Bounds every Accessibility request so a busy app cannot stall the keyboard.
    private static let messagingTimeout: Float = 0.25
    /// How long to skip requests to an app after one of them timed out.
    private static let unresponsiveBackoff: Duration = .seconds(1)

    private let systemWideElement = AXUIElementCreateSystemWide()
    private var unresponsiveApplications: [pid_t: ContinuousClock.Instant] = [:]
    private let editableTextRoles: Set<String> = [
        kAXComboBoxRole as String,
        kAXTextAreaRole as String,
        kAXTextFieldRole as String,
    ]

    // MARK: - Initialization
    private init() {
        // The default timeout is several seconds. Setting it on the system-wide
        // element applies it to every element this process messages.
        AXUIElementSetMessagingTimeout(systemWideElement, Self.messagingTimeout)
        refreshAuthorizationStatus()
    }

    // MARK: - Authorization
    @discardableResult
    func refreshAuthorizationStatus() -> Bool {
        isAuthorized = AXIsProcessTrusted()
        return isAuthorized
    }

    @discardableResult
    func requestAuthorization() -> Bool {
        let options =
            [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue(): kCFBooleanTrue as Any
            ] as CFDictionary

        isAuthorized = AXIsProcessTrustedWithOptions(options)
        return isAuthorized
    }

    // MARK: - Focused Target
    func focusedKeyboardTarget() throws -> FocusedKeyboardTarget {
        guard refreshAuthorizationStatus() else {
            throw AccessibilityFocusError.accessibilityNotAuthorized
        }

        let context = try focusedKeyboardContext()

        if let focusedElement = context.focusedElement, isSecureTextInput(focusedElement) {
            throw AccessibilityFocusError.secureTextInput
        }

        if let focusedElement = context.focusedElement,
            let textElement = editableTextElement(for: focusedElement)
        {
            return FocusedKeyboardTarget(
                processIdentifier: context.processIdentifier,
                applicationName: context.applicationName,
                applicationElement: context.applicationElement,
                focusedTextElement: textElement,
                focusedWindow: context.focusedWindow,
                route: .textElement,
                focusedElement: CFEqual(textElement, focusedElement) ? nil : focusedElement
            )
        }

        if let focusedWindow = context.focusedWindow {
            return FocusedKeyboardTarget(
                processIdentifier: context.processIdentifier,
                applicationName: context.applicationName,
                applicationElement: context.applicationElement,
                focusedTextElement: nil,
                focusedWindow: focusedWindow,
                route: .window,
                focusedElement: context.focusedElement
            )
        }

        return FocusedKeyboardTarget(
            processIdentifier: context.processIdentifier,
            applicationName: context.applicationName,
            applicationElement: context.applicationElement,
            focusedTextElement: nil,
            focusedWindow: nil,
            route: .application,
            focusedElement: context.focusedElement
        )
    }

    func keyboardTargetDebugSnapshot() -> KeyboardTargetDebugSnapshot {
        let capturedAt = Date.now

        guard refreshAuthorizationStatus() else {
            return KeyboardTargetDebugSnapshot(
                capturedAt: capturedAt,
                isAuthorized: false,
                canSendKeystrokes: false,
                hasFocusedTextInput: false,
                route: nil,
                processIdentifier: nil,
                applicationName: nil,
                focusedWindow: nil,
                focusedElement: nil,
                focusedText: nil,
                errorDescription: AccessibilityFocusError.accessibilityNotAuthorized
                    .localizedDescription
            )
        }

        do {
            let context = try focusedKeyboardContext()
            let focusedElement = context.focusedElement.map(debugInfo(for:))
            let focusedWindow = context.focusedWindow.map(debugInfo(for:))
            let route = route(
                focusedElement: context.focusedElement,
                focusedWindow: context.focusedWindow
            )
            let isSecureTextInput = focusedElement?.isSecureTextInput == true
            let hasFocusedTextInput = route == .textElement && !isSecureTextInput

            return KeyboardTargetDebugSnapshot(
                capturedAt: capturedAt,
                isAuthorized: true,
                canSendKeystrokes: route != nil && !isSecureTextInput,
                hasFocusedTextInput: hasFocusedTextInput,
                route: isSecureTextInput ? nil : route,
                processIdentifier: context.processIdentifier,
                applicationName: context.applicationName,
                focusedWindow: focusedWindow,
                focusedElement: focusedElement,
                focusedText: focusedTextValue(
                    for: context.focusedElement,
                    route: route,
                    isSecureTextInput: isSecureTextInput
                ),
                errorDescription: isSecureTextInput
                    ? AccessibilityFocusError.secureTextInput.localizedDescription
                    : nil
            )
        }
        catch {
            return KeyboardTargetDebugSnapshot(
                capturedAt: capturedAt,
                isAuthorized: true,
                canSendKeystrokes: false,
                hasFocusedTextInput: false,
                route: nil,
                processIdentifier: nil,
                applicationName: nil,
                focusedWindow: nil,
                focusedElement: nil,
                focusedText: nil,
                errorDescription: error.localizedDescription
            )
        }
    }

    // MARK: - Prediction Eligibility
    func predictionSnapshot(
        for target: FocusedKeyboardTarget,
        language: String
    ) -> PredictionContextSnapshot {
        guard target.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return .ineligible }
        guard let element = target.focusedTextElement else {
            return .unreadable(target, selection: nil)
        }
        var settable = DarwinBoolean(false)
        let result = request(element) {
            AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        }
        let isValueSettable = result == .success && settable.boolValue
        let snapshot = PredictionContextSnapshot(
            target: target,
            value: textValue(for: element, includesText: isValueSettable),
            language: language,
            isValueSettable: isValueSettable,
            textForRange: { self.string(for: $0, in: element) }
        )
        // Text reads are not atomic. Reject them if focus moved in the meantime.
        return isStillFocused(target) ? snapshot : .ineligible
    }

    // MARK: - Focus Revalidation
    /// Confirms focus stayed on the target with two requests instead of resolving it again.
    private func isStillFocused(_ target: FocusedKeyboardTarget) -> Bool {
        guard let application = try? focusedApplicationElement(),
            (try? processIdentifier(for: application)) == target.processIdentifier,
            let focusedElement: AXUIElement = try? copyAttribute(
                kAXFocusedUIElementAttribute as CFString,
                from: application
            )
        else { return false }
        return CFEqual(focusedElement, target.focusedElement ?? target.targetElement)
    }

    // MARK: - Accessibility Helpers
    private func focusedKeyboardContext() throws -> FocusedKeyboardContext {
        let applicationElement = try focusedApplicationElement()
        let processIdentifier = try processIdentifier(for: applicationElement)
        let applicationName = NSRunningApplication(
            processIdentifier: processIdentifier
        )?.localizedName
        let focusedElement: AXUIElement? = try? copyAttribute(
            kAXFocusedUIElementAttribute as CFString,
            from: applicationElement
        )
        let focusedWindow: AXUIElement? = try? copyAttribute(
            kAXFocusedWindowAttribute as CFString,
            from: applicationElement
        )

        return FocusedKeyboardContext(
            processIdentifier: processIdentifier,
            applicationName: applicationName,
            applicationElement: applicationElement,
            focusedElement: focusedElement,
            focusedWindow: focusedWindow
        )
    }

    private func focusedApplicationElement() throws -> AXUIElement {
        if let focusedApplication: AXUIElement = try? copyAttribute(
            kAXFocusedApplicationAttribute as CFString,
            from: systemWideElement
        ) {
            return focusedApplication
        }

        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            throw AccessibilityFocusError.focusedApplicationUnavailable
        }

        return AXUIElementCreateApplication(frontmostApplication.processIdentifier)
    }

    private func processIdentifier(for element: AXUIElement) throws -> pid_t {
        var processIdentifier = pid_t()
        let result = AXUIElementGetPid(element, &processIdentifier)

        guard result == .success else {
            throw AccessibilityFocusError.focusedApplicationPIDUnavailable(result)
        }

        return processIdentifier
    }

    private func copyAttribute<Value>(
        _ attribute: CFString,
        from element: AXUIElement
    ) throws -> Value {
        var rawValue: AnyObject?
        let result = request(element) {
            AXUIElementCopyAttributeValue(element, attribute, &rawValue)
        }
        let attributeName = attribute as String

        guard result == .success else {
            throw AccessibilityFocusError.attributeUnavailable(attributeName, result)
        }

        guard let value = rawValue as? Value else {
            throw AccessibilityFocusError.invalidAttributeValue(attributeName)
        }

        return value
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        let value: String? = try? copyAttribute(attribute, from: element)

        return value
    }

    private func integerAttribute(_ attribute: CFString, from element: AXUIElement) -> Int? {
        let number: NSNumber? = try? copyAttribute(attribute, from: element)

        return number?.intValue
    }

    // MARK: - Range-Based Accessibility Text
    private func string(for range: AccessibilityTextRange, in element: AXUIElement) -> String? {
        var range = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        let result = request(element) {
            AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForRangeParameterizedAttribute as CFString,
                parameter,
                &value
            )
        }
        guard result == .success else { return nil }
        return value as? String
    }

    private func rangeAttribute(_ attribute: CFString, from element: AXUIElement) -> CFRange? {
        let value: AXValue? = try? copyAttribute(attribute, from: element)
        var range = CFRange()

        guard let value, AXValueGetValue(value, .cfRange, &range) else {
            return nil
        }

        return range
    }

    // MARK: - Unresponsive Applications
    /// Sends one request, skipping apps that recently timed out. A hung app would
    /// otherwise cost the full timeout for every request in a capture.
    private func request(_ element: AXUIElement, _ body: () -> AXError) -> AXError {
        var processIdentifier = pid_t()
        guard AXUIElementGetPid(element, &processIdentifier) == .success else { return body() }
        if let retry = unresponsiveApplications[processIdentifier] {
            guard ContinuousClock.now >= retry else { return .cannotComplete }
            unresponsiveApplications[processIdentifier] = nil
        }
        let result = body()
        if result == .cannotComplete {
            unresponsiveApplications[processIdentifier] = .now + Self.unresponsiveBackoff
        }
        return result
    }

    // MARK: - Editable Text
    /// Returns the element holding the focused editable text. Web editors can focus a
    /// node nested inside the editable root, which they expose as its ancestor.
    private func editableTextElement(for element: AXUIElement) -> AXUIElement? {
        if isEditableTextElement(element) { return element }
        guard
            let ancestor: AXUIElement = try? copyAttribute(
                "AXEditableAncestor" as CFString,
                from: element
            ),
            isEditableTextElement(ancestor)
        else { return nil }
        return ancestor
    }

    private func isEditableTextElement(_ element: AXUIElement) -> Bool {
        guard let role = stringAttribute(kAXRoleAttribute as CFString, from: element) else {
            return false
        }

        return editableTextRoles.contains(role)
    }

    private func isSecureTextInput(_ element: AXUIElement) -> Bool {
        stringAttribute(kAXSubroleAttribute as CFString, from: element) == kAXSecureTextFieldSubrole
            as String
    }

    private func route(
        focusedElement: AXUIElement?,
        focusedWindow: AXUIElement?
    ) -> AccessibilityFocusRoute? {
        if let focusedElement, editableTextElement(for: focusedElement) != nil {
            return .textElement
        }

        if focusedWindow != nil {
            return .window
        }

        return .application
    }

    private func debugInfo(for element: AXUIElement) -> AccessibilityElementDebugInfo {
        let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: element)

        return AccessibilityElementDebugInfo(
            role: role,
            subrole: subrole,
            roleDescription: stringAttribute(
                kAXRoleDescriptionAttribute as CFString,
                from: element
            ),
            title: stringAttribute(kAXTitleAttribute as CFString, from: element),
            isSecureTextInput: subrole == kAXSecureTextFieldSubrole as String
        )
    }

    private func focusedTextValue(
        for element: AXUIElement?,
        route: AccessibilityFocusRoute?,
        isSecureTextInput: Bool
    ) -> FocusedTextValue? {
        guard let element, route == .textElement, !isSecureTextInput,
            let textElement = editableTextElement(for: element)
        else { return nil }

        return textValue(for: textElement)
    }

    private func textValue(for element: AXUIElement, includesText: Bool = true) -> FocusedTextValue
    {
        let text =
            includesText ? stringAttribute(kAXValueAttribute as CFString, from: element) : nil
        let selectedText = stringAttribute(kAXSelectedTextAttribute as CFString, from: element)
        let selectedRange = rangeAttribute(kAXSelectedTextRangeAttribute as CFString, from: element)
        let numberOfCharacters =
            includesText
            ? integerAttribute(
                kAXNumberOfCharactersAttribute as CFString,
                from: element
            ) : nil

        return FocusedTextValue(
            text: text,
            selectedText: selectedText?.isEmpty == false ? selectedText : nil,
            selectedRange: selectedRange.map {
                AccessibilityTextRange(location: max(0, $0.location), length: max(0, $0.length))
            },
            numberOfCharacters: numberOfCharacters
        )
    }

}
