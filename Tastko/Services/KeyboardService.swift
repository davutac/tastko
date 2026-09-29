import CoreGraphics
import Foundation
import Observation

// MARK: - KeyboardService
/// The single entry point for keyboard output.
///
/// Keystrokes arrive fully resolved: their flags already include latched, held, and
/// Caps Lock state (see `KeyResolver`), and they are delivered as given. The
/// service gates input on the lock screen, reports typing to the prediction
/// context, and records a receipt or error for every delivery.
@Observable
@MainActor
final class KeyboardService {
    static let shared = KeyboardService()

    let physicalKeyboard: PhysicalKeyboardState

    var inputDidChange: (() -> Void)?
    weak var typingObserver: (any KeyboardTypingObserving)?

    private(set) var isScreenLocked = false
    /// Changes whenever held input is cancelled, so pending UI work can tell it is stale.
    private(set) var inputSession = UUID()
    private(set) var lastError: KeyboardServiceError?
    private(set) var lastReceipt: KeyboardDeliveryReceipt?

    @ObservationIgnored private let synthesizer: KeyEventSynthesizer
    @ObservationIgnored private let targetResolver: any KeyboardTargetResolving
    @ObservationIgnored private let eventPoster: any KeyboardEventPosting
    @ObservationIgnored private let systemControlPerformer: any SystemControlPerforming
    @ObservationIgnored private let canPostEvents: () -> Bool
    @ObservationIgnored private let toggleSystemCapsLock: @MainActor () throws -> Bool
    @ObservationIgnored private var lockScreenInputEnabled = false

    // MARK: - Initialization
    convenience init() {
        self.init(
            targetResolver: AccessibilityService.shared,
            eventPoster: CGKeyboardEventPoster(),
            canPostEvents: {
                (getuid() != 0 || LoginWindowSession.isActive) && CGPreflightPostEventAccess()
            },
            physicalKeyboard: .shared
        )
    }

    init(
        targetResolver: any KeyboardTargetResolving,
        eventPoster: any KeyboardEventPosting,
        systemControlPerformer: any SystemControlPerforming = MacOSSystemControlPerformer(),
        canPostEvents: @escaping () -> Bool = { CGPreflightPostEventAccess() },
        physicalKeyboard: PhysicalKeyboardState? = nil,
        toggleSystemCapsLock: @escaping @MainActor () throws -> Bool = SystemCapsLock.toggle
    ) {
        let physicalKeyboard = physicalKeyboard ?? PhysicalKeyboardState()
        self.physicalKeyboard = physicalKeyboard
        self.synthesizer = KeyEventSynthesizer(poster: eventPoster) {
            physicalKeyboard.snapshot.modifierFlags
        }
        self.targetResolver = targetResolver
        self.eventPoster = eventPoster
        self.systemControlPerformer = systemControlPerformer
        self.canPostEvents = canPostEvents
        self.toggleSystemCapsLock = toggleSystemCapsLock
    }

    // MARK: - Modifier State
    /// One-shot modifiers that apply to the next key.
    var latchedModifiers: Set<ModifierKey> { Set(synthesizer.modifiers.latched) }

    /// Modifiers held physically, plus Fn while Tastko holds it.
    var heldModifiers: Set<ModifierKey> {
        physicalKeyboard.snapshot.modifiers
            .union(synthesizer.modifiers.isFunctionHeld ? [.function] : [])
    }

    var effectiveModifiers: Set<ModifierKey> { latchedModifiers.union(heldModifiers) }

    var isCapsLockEnabled: Bool { physicalKeyboard.snapshot.isCapsLockEnabled }

    /// Flags a key pressed now would carry.
    var modifierFlags: KeyModifiers {
        effectiveModifiers.flags.union(isCapsLockEnabled ? .capsLock : [])
    }

    // MARK: - Keystrokes
    /// Presses and releases a key. Latched modifiers the stroke carries are consumed.
    @discardableResult
    func tap(_ stroke: KeyStroke) throws -> KeyboardDeliveryReceipt {
        if stroke.key == .capsLock { return try toggleCapsLock() }
        return try deliverInput {
            notifyPreparingInput()
            try synthesizer.tap(stroke)
            notifyPosted(stroke)
            return .systemKeyEvent(summary: "key(\(stroke.key))")
        }
    }

    /// Holds a key down until `endPress(_:modifiers:)`.
    func beginPress(_ stroke: KeyStroke) throws -> KeyPress {
        var press: KeyPress?
        try deliverInput {
            notifyPreparingInput()
            press = try synthesizer.beginPress(stroke)
            notifyPosted(stroke)
            return .systemKeyEvent(summary: "key(\(stroke.key)) pressed")
        }
        guard let press else { throw KeyboardServiceError.eventCreationFailed }
        return press
    }

    /// Posts an autorepeat for a held key. Pass `modifiers` to follow re-resolved
    /// flags; without them the press follows physical modifier changes.
    func repeatPress(_ press: KeyPress, modifiers: KeyModifiers? = nil) throws {
        do {
            try checkLockScreenInput()
            notifyPreparingInput()
            if let stroke = try synthesizer.repeatPress(press, modifiers: modifiers) {
                notifyPosted(stroke)
            }
        }
        catch { throw recordFailure(error) }
    }

    func endPress(_ press: KeyPress, modifiers: KeyModifiers? = nil) throws {
        guard synthesizer.isHolding(press) else { return }
        try deliver {
            try synthesizer.endPress(press, modifiers: modifiers)
            return .systemKeyEvent(summary: "key released")
        }
    }

    /// Releases every held key and invalidates the current input session.
    func cancelPresses() {
        inputSession = UUID()
        guard synthesizer.hasPresses else { return }
        _ = try? deliver {
            try synthesizer.endAllPresses()
            return .systemKeyEvent(summary: "held keys released")
        }
    }

    // MARK: - Modifier Keys
    /// Latches a one-shot modifier for the next key, or releases its latch.
    @discardableResult
    func toggleLatch(_ modifier: ModifierKey) throws -> KeyboardDeliveryReceipt {
        if modifier == .function { return try toggleFunction() }
        return try deliverInput {
            try synthesizer.toggleLatch(modifier)
            return .modifierState(summary: "modifier(\(modifier) toggled)")
        }
    }

    @discardableResult
    func tapModifier(_ modifier: ModifierKey) throws -> KeyboardDeliveryReceipt {
        if modifier == .function { return try toggleFunction() }
        return try deliverInput {
            try synthesizer.tapModifier(modifier)
            return .systemKeyEvent(summary: "modifier(\(modifier))")
        }
    }

    /// Holds Fn down across keys, or releases Tastko's hold.
    @discardableResult
    func toggleFunction() throws -> KeyboardDeliveryReceipt {
        if synthesizer.modifiers.isFunctionHeld {
            return try deliver {
                try synthesizer.releaseFunction()
                return .systemKeyEvent(summary: "Fn released")
            }
        }
        return try deliverInput {
            try synthesizer.pressFunction()
            return .systemKeyEvent(summary: "Fn pressed")
        }
    }

    @discardableResult
    func toggleCapsLock() throws -> KeyboardDeliveryReceipt {
        try deliverInput {
            let isEnabled = try toggleSystemCapsLock()
            physicalKeyboard.refresh()
            try synthesizer.postCapsLock(isEnabled: isEnabled)
            return .systemKeyEvent(summary: "caps lock \(isEnabled ? "enabled" : "disabled")")
        }
    }

    /// Releases held keys, latched modifiers, and Fn. Failures are recorded, not thrown.
    func releaseAll() {
        cancelPresses()
        do { try synthesizer.releaseModifiers() }
        catch { _ = recordFailure(error) }
        if synthesizer.modifiers.isFunctionHeld { _ = try? toggleFunction() }
    }

    // MARK: - Text
    /// Types text into the focused element and consumes latched modifiers.
    @discardableResult
    func type(_ text: String) throws -> KeyboardDeliveryReceipt {
        guard !text.isEmpty else { return recordSuccess(.noOperation(summary: "empty text")) }
        return try deliverInput {
            if isScreenLocked {
                try eventPoster.postTextToSystemFocus(text)
                try synthesizer.releaseModifiers()
                return .systemKeyEvent(summary: "Input submitted to system focus")
            }
            let target = try targetResolver.focusedKeyboardTarget()
            typingObserver?.prepareForInput()
            try eventPoster.postText(text, to: target)
            typingObserver?.didPostText(text)
            try synthesizer.releaseModifiers()
            return KeyboardDeliveryReceipt(
                method: .textEvent,
                target: target,
                summary: "text(\(text.count) characters)"
            )
        }
    }

    /// Inserts a prediction into the target it was validated against.
    @discardableResult
    func insertPrediction(
        _ text: String,
        deletingBackward count: Int = 0,
        into target: FocusedKeyboardTarget
    ) throws -> KeyboardDeliveryReceipt {
        try deliver {
            guard !isScreenLocked else {
                throw KeyboardServiceError.deliveryFailed("Predictions are paused while locked.")
            }
            typingObserver?.prepareForInput()
            if count > 0 {
                typingObserver?.resetTypingSession()
                try eventPoster.replacePrefix(count, with: text, to: target)
            }
            else if !text.isEmpty {
                try eventPoster.postText(text, to: target)
                typingObserver?.didPostText(text)
            }
            return KeyboardDeliveryReceipt(
                method: .textEvent,
                target: target,
                summary: "prediction(\(text.count) characters)"
            )
        }
    }

    // MARK: - System Controls
    @discardableResult
    func perform(_ control: SystemControl) async throws -> KeyboardDeliveryReceipt {
        do {
            try synthesizer.releaseModifiers()
            try await systemControlPerformer.perform(control)
            return recordSuccess(.systemKeyEvent(summary: "system control \(control.rawValue)"))
        }
        catch { throw recordFailure(error) }
    }

    // MARK: - Lock-Screen Input
    func setScreenLocked(_ locked: Bool, allowsInput: Bool) {
        guard isScreenLocked != locked || lockScreenInputEnabled != allowsInput else { return }
        lastError = nil
        releaseAll()
        isScreenLocked = locked
        lockScreenInputEnabled = allowsInput
        physicalKeyboard.reset()
        inputSession = UUID()
        typingObserver?.resetTypingSession()
        lastReceipt = nil
    }

    private func checkLockScreenInput() throws {
        guard isScreenLocked else { return }
        guard lockScreenInputEnabled else {
            throw KeyboardServiceError.deliveryFailed(
                "Lock-screen keyboard is disabled in Settings."
            )
        }
        guard canPostEvents() else {
            throw KeyboardServiceError.accessibility(.accessibilityNotAuthorized)
        }
    }

    // MARK: - Typing Observation
    private func notifyPreparingInput() {
        if !isScreenLocked { typingObserver?.prepareForInput() }
    }

    private func notifyPosted(_ stroke: KeyStroke) {
        if !isScreenLocked { typingObserver?.didPostKey(stroke) }
    }

    // MARK: - Delivery Recording
    /// Runs new input after the lock-screen check and records the outcome.
    @discardableResult
    private func deliverInput(
        _ body: () throws -> KeyboardDeliveryReceipt
    ) throws -> KeyboardDeliveryReceipt {
        try deliver {
            try checkLockScreenInput()
            return try body()
        }
    }

    /// Records the outcome of a delivery. Releases skip the lock-screen check so
    /// keys pressed before a lock can always come back up.
    @discardableResult
    private func deliver(
        _ body: () throws -> KeyboardDeliveryReceipt
    ) throws -> KeyboardDeliveryReceipt {
        do { return recordSuccess(try body()) }
        catch { throw recordFailure(error) }
    }

    private func recordSuccess(_ receipt: KeyboardDeliveryReceipt) -> KeyboardDeliveryReceipt {
        lastError = nil
        guard !isScreenLocked else {
            lastReceipt = nil
            return KeyboardDeliveryReceipt(
                method: receipt.method,
                summary: "Lock-screen input; acceptance unverified"
            )
        }
        lastReceipt = receipt
        inputDidChange?()
        return receipt
    }

    private func recordFailure(_ error: any Error) -> KeyboardServiceError {
        typingObserver?.resetTypingSession()
        let serviceError = KeyboardServiceError(error)
        lastError = serviceError
        return serviceError
    }
}

// MARK: - AccessibilityService KeyboardTargetResolving
extension AccessibilityService: KeyboardTargetResolving {}
