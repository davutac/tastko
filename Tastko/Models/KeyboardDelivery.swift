import CoreGraphics
import Foundation

// MARK: - KeyboardTypingObserving
@MainActor
protocol KeyboardTypingObserving: AnyObject {
    func prepareForInput()
    func didPostText(_ text: String)
    func didPostKey(_ stroke: KeyStroke)
    func resetTypingSession()
}

// MARK: - KeyboardTargetResolving
@MainActor
protocol KeyboardTargetResolving {
    func focusedKeyboardTarget() throws -> FocusedKeyboardTarget
}

// MARK: - KeyboardEventPosting
@MainActor
protocol KeyboardEventPosting {
    func postText(_ text: String, to target: FocusedKeyboardTarget) throws
    func replacePrefix(_ count: Int, with text: String, to target: FocusedKeyboardTarget) throws
    func postTextToSystemFocus(_ text: String) throws
    func postKey(_ key: Key, modifiers: KeyModifiers, keyDown: Bool) throws
    func postKeyRepeat(_ key: Key, modifiers: KeyModifiers) throws
}

extension KeyboardEventPosting {
    // MARK: - Repeat Delivery
    func postKeyRepeat(_ key: Key, modifiers: KeyModifiers) throws {
        try postKey(key, modifiers: modifiers, keyDown: true)
    }
}

// MARK: - KeyPress
/// A key held down by `KeyboardService.beginPress(_:)` until `endPress(_:)` releases it.
nonisolated struct KeyPress: Hashable, Sendable {
    private let id = UUID()

    init() {}
}

// MARK: - KeyboardDeliveryMethod
nonisolated enum KeyboardDeliveryMethod: Hashable, Sendable {
    case noOperation
    case modifierState
    case textEvent
    case keyEvent
}

// MARK: - KeyboardDeliveryReceipt
nonisolated struct KeyboardDeliveryReceipt: Hashable, Sendable {
    let method: KeyboardDeliveryMethod
    let route: AccessibilityFocusRoute?
    let processIdentifier: pid_t?
    let applicationName: String?
    let summary: String

    // MARK: - Untargeted Receipts
    init(
        method: KeyboardDeliveryMethod,
        route: AccessibilityFocusRoute? = nil,
        processIdentifier: pid_t? = nil,
        applicationName: String? = nil,
        summary: String
    ) {
        self.method = method
        self.route = route
        self.processIdentifier = processIdentifier
        self.applicationName = applicationName
        self.summary = summary
    }

    // MARK: - Targeted Receipts
    init(method: KeyboardDeliveryMethod, target: FocusedKeyboardTarget, summary: String) {
        self.init(
            method: method,
            route: target.route,
            processIdentifier: target.processIdentifier,
            applicationName: target.applicationName,
            summary: summary
        )
    }

    static func noOperation(summary: String) -> KeyboardDeliveryReceipt {
        KeyboardDeliveryReceipt(method: .noOperation, summary: summary)
    }

    static func modifierState(summary: String) -> KeyboardDeliveryReceipt {
        KeyboardDeliveryReceipt(method: .modifierState, summary: summary)
    }

    static func systemKeyEvent(summary: String) -> KeyboardDeliveryReceipt {
        KeyboardDeliveryReceipt(method: .keyEvent, summary: summary)
    }
}

// MARK: - KeyboardServiceError
nonisolated enum KeyboardServiceError: Equatable, LocalizedError, Sendable {
    case accessibility(AccessibilityFocusError)
    case eventCreationFailed
    case deliveryFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessibility(let error):
            error.localizedDescription
        case .eventCreationFailed:
            "A keyboard event could not be created."
        case .deliveryFailed(let message):
            message
        }
    }
}

// MARK: - KeyboardServiceError Conversion
extension KeyboardServiceError {
    nonisolated init(_ error: any Error) {
        if let serviceError = error as? KeyboardServiceError {
            self = serviceError
        }
        else if let accessibilityError = error as? AccessibilityFocusError {
            self = .accessibility(accessibilityError)
        }
        else {
            self = .deliveryFailed(error.localizedDescription)
        }
    }
}
