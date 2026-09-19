import CoreGraphics
import Foundation
import Observation

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

    static func noOperation(summary: String) -> KeyboardDeliveryReceipt {
        KeyboardDeliveryReceipt(
            method: .noOperation,
            route: nil,
            processIdentifier: nil,
            applicationName: nil,
            summary: summary
        )
    }

    static func modifierState(summary: String) -> KeyboardDeliveryReceipt {
        KeyboardDeliveryReceipt(
            method: .modifierState,
            route: nil,
            processIdentifier: nil,
            applicationName: nil,
            summary: summary
        )
    }

    static func systemKeyEvent(summary: String) -> KeyboardDeliveryReceipt {
        KeyboardDeliveryReceipt(
            method: .keyEvent,
            route: nil,
            processIdentifier: nil,
            applicationName: nil,
            summary: summary
        )
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

// MARK: - KeyboardService
@Observable
@MainActor
final class KeyboardService {
    static let shared = KeyboardService()

    let physicalKeyboard: PhysicalKeyboardState

    var heldModifiers: Set<ModifierKey> {
        physicalKeyboard.snapshot.modifiers.union(functionPress == nil ? [] : [.function])
    }

    var effectiveModifiers: Set<ModifierKey> {
        activeOneShotModifiers.union(heldModifiers)
    }

    var isCapsLockEnabled: Bool { physicalKeyboard.snapshot.isCapsLockEnabled }
    var effectiveCapsLockEnabled: Bool { isCapsLockEnabled }

    private var heldModifierFlags: KeyModifiers {
        physicalKeyboard.snapshot.modifierFlags.union(functionPress == nil ? [] : [.function])
    }

    var inputDidChange: (() -> Void)?
    weak var typingObserver: (any KeyboardTypingObserving)?

    private let targetResolver: KeyboardTargetResolving
    private let eventPoster: KeyboardEventPosting
    private let systemControlPerformer: any SystemControlPerforming
    private let canPostEvents: () -> Bool
    private(set) var isScreenLocked = false
    private(set) var inputSession = UUID()
    private var lockScreenInputEnabled = false

    private(set) var lastError: KeyboardServiceError?
    private(set) var lastReceipt: KeyboardDeliveryReceipt?
    private(set) var activeOneShotModifiers: Set<ModifierKey> = []
    private var activeOneShotModifierOrder: [ModifierKey] = []
    private var postedModifiers: [ModifierKey] = []
    private var functionPress: UUID?
    private struct HeldKeyPress {
        let stroke: KeyStroke
        let modifiers: [ModifierKey]
        let initialHeldFlags: KeyModifiers
        var keyIsDown = true
    }
    private var keyPresses: [UUID: HeldKeyPress] = [:]
    private let toggleSystemCapsLock: @MainActor () throws -> Bool

    // MARK: - Initialization
    init() {
        self.physicalKeyboard = .shared
        self.targetResolver = AccessibilityService.shared
        self.eventPoster = CGKeyboardEventPoster()
        self.systemControlPerformer = MacOSSystemControlPerformer()
        self.toggleSystemCapsLock = SystemCapsLock.toggle
        self.canPostEvents = {
            (getuid() != 0 || LoginWindowSession.isActive) && CGPreflightPostEventAccess()
        }
    }

    init(
        targetResolver: KeyboardTargetResolving,
        eventPoster: KeyboardEventPosting,
        systemControlPerformer: any SystemControlPerforming = MacOSSystemControlPerformer(),
        canPostEvents: @escaping () -> Bool = { CGPreflightPostEventAccess() },
        physicalKeyboard: PhysicalKeyboardState? = nil,
        toggleSystemCapsLock: @escaping @MainActor () throws -> Bool = SystemCapsLock.toggle
    ) {
        self.physicalKeyboard = physicalKeyboard ?? PhysicalKeyboardState()
        self.targetResolver = targetResolver
        self.eventPoster = eventPoster
        self.systemControlPerformer = systemControlPerformer
        self.canPostEvents = canPostEvents
        self.toggleSystemCapsLock = toggleSystemCapsLock
    }

    // MARK: - Lock-Screen Input
    func setScreenLocked(_ locked: Bool, allowsInput: Bool) {
        guard isScreenLocked != locked || lockScreenInputEnabled != allowsInput else { return }
        lastError = nil
        releaseAllModifiers()
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

    // MARK: - Key Actions
    @discardableResult
    func perform(
        _ action: KeyAction,
        behavior: KeyPressBehavior = .pressAndRelease
    ) async throws -> KeyboardDeliveryReceipt {
        switch action {
        case .none:
            recordSuccess(.noOperation(summary: "key action none"))
        case .text(let text):
            try await type(text, consumesActiveOneShotModifiers: true)
        case .keyStroke(let stroke):
            try await press(stroke, consumesActiveOneShotModifiers: true)
        case .modifier(let modifier):
            try await perform(modifier, behavior: behavior)
        case .cycleKeyboardLanguage:
            recordSuccess(.noOperation(summary: "keyboard language cycle"))
        case .toggleFunctionToolbar:
            recordSuccess(.noOperation(summary: "function toolbar visibility handled by window"))
        }
    }

    // MARK: - Function Toolbar
    @discardableResult
    func pressFunctionToolbarKey(_ key: Key) async throws -> KeyboardDeliveryReceipt {
        let modifiers = consumeActiveOneShotModifiers().filter { $0 != .function }
        return try press(KeyStroke(key), latchedModifiers: modifiers)
    }

    @discardableResult
    func performSystemControl(_ control: SystemControl) async throws -> KeyboardDeliveryReceipt {
        do {
            try clearActiveOneShotModifiers()
            try await systemControlPerformer.perform(control)
            return recordSuccess(.systemKeyEvent(summary: "system control \(control.rawValue)"))
        }
        catch {
            throw recordFailure(error)
        }
    }

    @discardableResult
    private func perform(
        _ modifier: ModifierKey,
        behavior: KeyPressBehavior
    ) async throws -> KeyboardDeliveryReceipt {
        if modifier == .function { return try toggleFunctionKey() }
        return switch behavior {
        case .pressAndRelease:
            try await pressAndRelease(modifier)
        case .oneShot:
            try toggleOneShotModifier(modifier)
        }
    }

    @discardableResult
    private func pressAndRelease(_ modifier: ModifierKey) async throws -> KeyboardDeliveryReceipt {
        do {
            try checkLockScreenInput()
            let wasPosted = postedModifiers.contains(modifier)
            try postModifierDown(modifier)
            if !wasPosted { try postModifierUp(modifier) }

            return recordSuccess(
                .systemKeyEvent(
                    summary: "modifier(\(modifier))"
                )
            )
        }
        catch {
            throw recordFailure(error)
        }
    }

    @discardableResult
    func toggleOneShotModifier(_ modifier: ModifierKey) throws -> KeyboardDeliveryReceipt {
        if modifier == .function { return try toggleFunctionKey() }
        do {
            try checkLockScreenInput()
            if activeOneShotModifiers.contains(modifier) {
                try postModifierUp(modifier)
                activeOneShotModifiers.remove(modifier)
                activeOneShotModifierOrder.removeAll { $0 == modifier }
            }
            else {
                try postModifierDown(modifier)
                activeOneShotModifiers.insert(modifier)
                activeOneShotModifierOrder.append(modifier)
            }
            return recordSuccess(.modifierState(summary: "modifier(\(modifier) toggled)"))
        }
        catch { throw recordFailure(error) }
    }

    // MARK: - Fn Toggle
    @discardableResult
    func toggleFunctionKey() throws -> KeyboardDeliveryReceipt {
        if let functionPress {
            try endFunctionPress(functionPress)
        }
        else {
            _ = try beginFunctionPress()
        }
        return recordSuccess(.systemKeyEvent(summary: "Fn toggled"))
    }

    // MARK: - Held Fn
    func beginFunctionPress() throws -> UUID? {
        do {
            try checkLockScreenInput()
            guard functionPress == nil, !physicalKeyboard.snapshot.modifiers.contains(.function)
            else { return nil }
            try eventPoster.postKey(
                .function,
                modifiers: modifierFlags(for: Set(postedModifiers)).union(heldModifierFlags)
                    .union(.function),
                keyDown: true
            )
            let token = UUID()
            functionPress = token
            _ = recordSuccess(.systemKeyEvent(summary: "Fn pressed"))
            return token
        }
        catch { throw recordFailure(error) }
    }

    // MARK: - Fn Release
    func endFunctionPress(_ token: UUID) throws {
        guard functionPress == token else { return }
        do {
            try eventPoster.postKey(
                .function,
                modifiers: modifierFlags(for: Set(postedModifiers))
                    .union(physicalKeyboard.snapshot.modifierFlags),
                keyDown: false
            )
            functionPress = nil
            _ = recordSuccess(.systemKeyEvent(summary: "Fn released"))
        }
        catch { throw recordFailure(error) }
    }

    // MARK: - Held Keys
    func beginKeyPress(_ stroke: KeyStroke, latchedModifiers: [ModifierKey]) throws -> UUID {
        let releases = latchedModifiers.filter { !activeOneShotModifiers.contains($0) }
        do {
            try checkLockScreenInput()
            try releaseUnclaimedModifiers(keeping: latchedModifiers)
            for modifier in latchedModifiers { try postModifierDown(modifier) }
            let flags = stroke.modifiers.union(modifierFlags(for: Set(latchedModifiers)))
                .union(functionPress == nil ? [] : [.function])
            let resolved = KeyStroke(stroke.key, modifiers: flags)
            if !isScreenLocked { typingObserver?.prepareForInput() }
            try eventPoster.postKey(stroke.key, modifiers: flags, keyDown: true)
            let token = UUID()
            keyPresses[token] = HeldKeyPress(
                stroke: resolved,
                modifiers: releases,
                initialHeldFlags: heldModifierFlags
            )
            if !isScreenLocked { typingObserver?.didPostKey(resolved) }
            _ = recordSuccess(.systemKeyEvent(summary: "key(\(stroke.key)) pressed"))
            return token
        }
        catch {
            postModifierUpsBestEffort(releases)
            throw recordFailure(error)
        }
    }

    // MARK: - Key Repeat
    func repeatKeyPress(_ token: UUID, modifiers: KeyModifiers? = nil) throws {
        guard let press = keyPresses[token], press.keyIsDown else { return }
        do {
            try checkLockScreenInput()
            let flags = currentFlags(for: press, resolved: modifiers)
            if !isScreenLocked { typingObserver?.prepareForInput() }
            try eventPoster.postKeyRepeat(press.stroke.key, modifiers: flags)
            if !isScreenLocked {
                typingObserver?.didPostKey(KeyStroke(press.stroke.key, modifiers: flags))
            }
        }
        catch { throw recordFailure(error) }
    }

    // MARK: - Key Release
    func endKeyPress(_ token: UUID, modifiers: KeyModifiers? = nil) throws {
        guard let press = keyPresses[token] else { return }
        do {
            if press.keyIsDown {
                try eventPoster.postKey(
                    press.stroke.key,
                    modifiers: currentFlags(for: press, resolved: modifiers),
                    keyDown: false
                )
                keyPresses[token]?.keyIsDown = false
            }
            try postModifierUps(press.modifiers)
            keyPresses.removeValue(forKey: token)
            _ = recordSuccess(.systemKeyEvent(summary: "key(\(press.stroke.key)) released"))
        }
        catch { throw recordFailure(error) }
    }

    // MARK: - Held-Key Flags
    private func currentFlags(for press: HeldKeyPress, resolved: KeyModifiers?) -> KeyModifiers {
        if let resolved { return resolved.union(functionPress == nil ? [] : [.function]) }
        let suppressed = press.initialHeldFlags.subtracting(press.stroke.modifiers)
        return press.stroke.modifiers.subtracting(press.initialHeldFlags)
            .union(heldModifierFlags.subtracting(suppressed))
    }

    // MARK: - Held-Key Cancellation
    func cancelKeyPresses() {
        inputSession = UUID()
        for token in Array(keyPresses.keys) {
            do { try endKeyPress(token) }
            catch { _ = recordFailure(error) }
        }
    }

    // MARK: - Input Cleanup
    func releaseAllModifiers() {
        cancelKeyPresses()
        do { try clearActiveOneShotModifiers() }
        catch { _ = recordFailure(error) }
        if let token = functionPress {
            do { try endFunctionPress(token) }
            catch { _ = recordFailure(error) }
        }
    }

    // MARK: - Text Input
    @discardableResult
    func type(_ text: String) async throws -> KeyboardDeliveryReceipt {
        try await type(text, consumesActiveOneShotModifiers: false)
    }

    @discardableResult
    private func type(
        _ text: String,
        consumesActiveOneShotModifiers: Bool
    ) async throws -> KeyboardDeliveryReceipt {
        guard !text.isEmpty else {
            return recordSuccess(.noOperation(summary: "empty text"))
        }

        do {
            try checkLockScreenInput()
            if isScreenLocked {
                try eventPoster.postTextToSystemFocus(text)
                if consumesActiveOneShotModifiers { try clearActiveOneShotModifiers() }
                return recordSuccess(.systemKeyEvent(summary: "Input submitted to system focus"))
            }
            let target = try targetResolver.focusedKeyboardTarget()

            typingObserver?.prepareForInput()
            try eventPoster.postText(text, to: target)
            typingObserver?.didPostText(text)

            if consumesActiveOneShotModifiers {
                try clearActiveOneShotModifiers()
            }

            return recordSuccess(
                receipt(
                    method: .textEvent,
                    target: target,
                    summary: "text(\(text.count) characters)"
                )
            )
        }
        catch {
            throw recordFailure(error)
        }
    }

    // MARK: - Prediction Delivery
    @discardableResult
    func type(
        _ text: String,
        deletingBackward count: Int = 0,
        toValidatedTarget target: FocusedKeyboardTarget
    ) throws
        -> KeyboardDeliveryReceipt
    {
        do {
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
            return recordSuccess(
                receipt(
                    method: .textEvent,
                    target: target,
                    summary: "prediction(\(text.count) characters)"
                )
            )
        }
        catch {
            throw recordFailure(error)
        }
    }

    // MARK: - Keystroke Input
    @discardableResult
    func press(_ key: Key, modifiers: KeyModifiers = []) async throws -> KeyboardDeliveryReceipt {
        try await press(KeyStroke(key, modifiers: modifiers))
    }

    @discardableResult
    func press(_ stroke: KeyStroke) async throws -> KeyboardDeliveryReceipt {
        try await press(stroke, consumesActiveOneShotModifiers: false)
    }

    @discardableResult
    func consumeActiveOneShotModifiers(for action: KeyAction = .none) -> [ModifierKey] {
        let modifiers = activeOneShotModifierOrder
        // Transfer the latch to the synchronous key delivery without releasing it early.
        activeOneShotModifiers.removeAll()
        activeOneShotModifierOrder.removeAll()
        guard case .keyStroke(let stroke) = action else { return modifiers }
        // The resolver may remove Shift to force lowercase on a Caps Lock right-click.
        return modifiers.filter { stroke.modifiers.isSuperset(of: $0.modifiers) }
    }

    // MARK: - Caps Lock
    @discardableResult
    func toggleCapsLock() throws -> KeyboardDeliveryReceipt {
        do {
            try checkLockScreenInput()
            let enabled = try toggleSystemCapsLock()
            physicalKeyboard.refresh()
            let flags = modifierFlags(for: Set(postedModifiers)).union(heldModifierFlags)
                .subtracting(.capsLock).union(enabled ? .capsLock : [])
            try eventPoster.postKey(.capsLock, modifiers: flags, keyDown: true)
            try eventPoster.postKey(.capsLock, modifiers: flags, keyDown: false)
            return recordSuccess(
                .systemKeyEvent(summary: "caps lock \(enabled ? "enabled" : "disabled")")
            )
        }
        catch { throw recordFailure(error) }
    }

    // MARK: - Keystroke Delivery
    @discardableResult
    private func press(
        _ stroke: KeyStroke,
        consumesActiveOneShotModifiers: Bool
    ) async throws -> KeyboardDeliveryReceipt {
        let latchedModifiers = activeOneShotModifierOrder

        if consumesActiveOneShotModifiers, stroke.key != .capsLock {
            consumeActiveOneShotModifiers()
        }

        return try press(stroke, latchedModifiers: latchedModifiers)
    }

    @discardableResult
    func press(
        _ stroke: KeyStroke,
        latchedModifiers: [ModifierKey],
        modifiersAreResolved: Bool = false
    ) throws -> KeyboardDeliveryReceipt {
        if stroke.key == .capsLock {
            return try toggleCapsLock()
        }

        do {
            try checkLockScreenInput()
            try releaseUnclaimedModifiers(keeping: latchedModifiers)
            let hardwareFlags = heldModifierFlags
            let modifiers = stroke.modifiers
                .union(modifierFlags(for: Set(latchedModifiers)))
                .union(modifiersAreResolved ? [] : hardwareFlags)
            let syntheticModifiers = latchedModifiers.filter {
                postedModifiers.contains($0) || hardwareFlags.intersection($0.modifiers).isEmpty
            }

            if !isScreenLocked { typingObserver?.prepareForInput() }
            try postChord(
                stroke,
                modifiers: modifiers,
                latchedModifiers: syntheticModifiers
            )
            if !isScreenLocked {
                typingObserver?.didPostKey(KeyStroke(stroke.key, modifiers: modifiers))
            }

            return recordSuccess(
                .systemKeyEvent(
                    summary: "key(\(stroke.key))"
                )
            )
        }
        catch {
            throw recordFailure(error)
        }
    }

    // MARK: - One-Shot Modifiers
    private func modifierFlags(for modifiers: Set<ModifierKey>) -> KeyModifiers {
        modifiers.reduce([]) { flags, modifier in
            flags.union(modifier.modifiers)
        }
    }

    // MARK: - Transferred Modifiers
    private func releaseUnclaimedModifiers(keeping modifiers: [ModifierKey]) throws {
        for modifier in postedModifiers
        where !modifiers.contains(modifier) && !activeOneShotModifiers.contains(modifier) {
            try postModifierUp(modifier)
        }
    }

    // MARK: - Modifier Cleanup
    private func clearActiveOneShotModifiers() throws {
        var firstError: (any Error)?
        for modifier in postedModifiers.reversed() {
            do { try postModifierUp(modifier) }
            catch { if firstError == nil { firstError = error } }
        }
        activeOneShotModifiers.removeAll()
        activeOneShotModifierOrder.removeAll()
        if let firstError { throw firstError }
    }

    // MARK: - Modifier Down
    private func postModifierDown(_ modifier: ModifierKey) throws {
        guard !postedModifiers.contains(modifier),
            heldModifierFlags.intersection(modifier.modifiers).isEmpty
        else { return }
        try eventPoster.postKey(
            modifier.key,
            modifiers: modifierFlags(for: Set(postedModifiers)).union(heldModifierFlags)
                .union(modifier.modifiers),
            keyDown: true
        )
        postedModifiers.append(modifier)
    }

    // MARK: - Modifier Up
    private func postModifierUp(_ modifier: ModifierKey) throws {
        guard postedModifiers.contains(modifier) else { return }
        let remaining = Set(postedModifiers).subtracting([modifier])
        try eventPoster.postKey(
            modifier.key,
            modifiers: modifierFlags(for: remaining).union(heldModifierFlags),
            keyDown: false
        )
        postedModifiers.removeAll { $0 == modifier }
    }

    // MARK: - Chord Events
    private func postChord(
        _ stroke: KeyStroke,
        modifiers: KeyModifiers,
        latchedModifiers: [ModifierKey]
    ) throws {
        var postedModifiers: [ModifierKey] = []
        var keyIsDown = false

        do {
            for modifier in latchedModifiers {
                try postModifierDown(modifier)
                if !activeOneShotModifiers.contains(modifier) {
                    postedModifiers.append(modifier)
                }
            }

            try eventPoster.postKey(
                stroke.key,
                modifiers: modifiers,
                keyDown: true
            )
            keyIsDown = true

            try eventPoster.postKey(
                stroke.key,
                modifiers: modifiers,
                keyDown: false
            )
            keyIsDown = false

            try postModifierUps(postedModifiers)
        }
        catch {
            if keyIsDown {
                try? eventPoster.postKey(
                    stroke.key,
                    modifiers: modifiers,
                    keyDown: false
                )
            }

            postModifierUpsBestEffort(postedModifiers)
            throw error
        }
    }

    private func postModifierUps(_ modifiers: [ModifierKey]) throws {
        for modifier in modifiers.reversed() { try postModifierUp(modifier) }
    }

    private func postModifierUpsBestEffort(_ modifiers: [ModifierKey]) {
        for modifier in modifiers.reversed() { try? postModifierUp(modifier) }
    }

    // MARK: - Receipts
    private func receipt(
        method: KeyboardDeliveryMethod,
        target: FocusedKeyboardTarget,
        summary: String
    ) -> KeyboardDeliveryReceipt {
        KeyboardDeliveryReceipt(
            method: method,
            route: target.route,
            processIdentifier: target.processIdentifier,
            applicationName: target.applicationName,
            summary: summary
        )
    }

    private func recordSuccess(_ receipt: KeyboardDeliveryReceipt) -> KeyboardDeliveryReceipt {
        lastError = nil
        if isScreenLocked {
            lastReceipt = nil
            return KeyboardDeliveryReceipt(
                method: receipt.method,
                route: nil,
                processIdentifier: nil,
                applicationName: nil,
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

// MARK: - KeyboardServiceError Conversion
extension KeyboardServiceError {
    fileprivate init(_ error: any Error) {
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
