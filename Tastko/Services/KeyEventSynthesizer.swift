import Observation

// MARK: - KeyEventSynthesizer
/// Turns keystrokes and modifier changes into paired key events.
///
/// Strokes are delivered with exactly the flags they carry. The synthesizer presses
/// the modifier keys those flags need, like a hardware keyboard would, and always
/// releases what it pressed. It holds no policy: permission, lock-screen, and
/// receipt handling belong to `KeyboardService`.
@Observable
@MainActor
final class KeyEventSynthesizer {
    private(set) var modifiers = ModifierLedger()

    @ObservationIgnored private var presses: [KeyPress: HeldPress] = [:]
    @ObservationIgnored private let poster: any KeyboardEventPosting
    @ObservationIgnored private let physicalFlags: () -> KeyModifiers

    // MARK: - HeldPress
    private struct HeldPress {
        let stroke: KeyStroke
        /// Modifier keys pressed for this key, released after its key up.
        let modifiers: [ModifierKey]
        let initialHeldFlags: KeyModifiers
        var isKeyDown = true
    }

    var hasPresses: Bool { !presses.isEmpty }

    func isHolding(_ press: KeyPress) -> Bool { presses[press] != nil }

    // MARK: - Initialization
    init(poster: any KeyboardEventPosting, physicalFlags: @escaping () -> KeyModifiers) {
        self.poster = poster
        self.physicalFlags = physicalFlags
    }

    // MARK: - Keystrokes
    func tap(_ stroke: KeyStroke) throws {
        let owned = try pressModifiers(for: stroke)
        var isKeyDown = false
        do {
            try poster.postKey(stroke.key, modifiers: stroke.modifiers, keyDown: true)
            isKeyDown = true
            try poster.postKey(stroke.key, modifiers: stroke.modifiers, keyDown: false)
            isKeyDown = false
            try release(owned)
        }
        catch {
            if isKeyDown {
                try? poster.postKey(stroke.key, modifiers: stroke.modifiers, keyDown: false)
            }
            releaseBestEffort(owned)
            throw error
        }
    }

    // MARK: - Held Keys
    func beginPress(_ stroke: KeyStroke) throws -> KeyPress {
        let owned = try pressModifiers(for: stroke)
        do {
            try poster.postKey(stroke.key, modifiers: stroke.modifiers, keyDown: true)
        }
        catch {
            releaseBestEffort(owned)
            throw error
        }
        let press = KeyPress()
        presses[press] = HeldPress(
            stroke: stroke,
            modifiers: owned,
            initialHeldFlags: modifiers.heldFlags(physical: physicalFlags())
        )
        return press
    }

    /// Posts an autorepeat event and returns the repeated stroke, or `nil` for a
    /// press that already ended.
    func repeatPress(_ press: KeyPress, modifiers flags: KeyModifiers?) throws -> KeyStroke? {
        guard let held = presses[press], held.isKeyDown else { return nil }
        let stroke = KeyStroke(held.stroke.key, modifiers: currentFlags(for: held, flags))
        try poster.postKeyRepeat(stroke.key, modifiers: stroke.modifiers)
        return stroke
    }

    /// Releases the key, then its modifiers. A failed release keeps the press so a
    /// later call can retry it without repeating the parts that succeeded.
    func endPress(_ press: KeyPress, modifiers flags: KeyModifiers?) throws {
        guard let held = presses[press] else { return }
        if held.isKeyDown {
            try poster.postKey(
                held.stroke.key,
                modifiers: currentFlags(for: held, flags),
                keyDown: false
            )
            presses[press]?.isKeyDown = false
        }
        try release(held.modifiers)
        presses[press] = nil
    }

    func endAllPresses() throws {
        try forEachCollectingFirstError(Array(presses.keys)) { try endPress($0, modifiers: nil) }
    }

    // MARK: - Held-Key Flags
    /// Follows physical modifier changes during a hold unless the caller re-resolved them.
    private func currentFlags(for held: HeldPress, _ resolved: KeyModifiers?) -> KeyModifiers {
        if let resolved { return resolved }
        let suppressed = held.initialHeldFlags.subtracting(held.stroke.modifiers)
        return held.stroke.modifiers.subtracting(held.initialHeldFlags)
            .union(modifiers.heldFlags(physical: physicalFlags()).subtracting(suppressed))
    }

    // MARK: - Latches
    func toggleLatch(_ modifier: ModifierKey) throws {
        if modifiers.latched.contains(modifier) {
            try release(modifier)
            modifiers.unlatch(modifier)
        }
        else {
            try press(modifier)
            modifiers.latch(modifier)
        }
    }

    /// Presses and releases a modifier key. A modifier Tastko already holds stays down.
    func tapModifier(_ modifier: ModifierKey) throws {
        let wasPressed = modifiers.pressed.contains(modifier)
        try press(modifier)
        if !wasPressed { try release(modifier) }
    }

    /// Releases every modifier key Tastko pressed and clears the latches, continuing
    /// past failures so one stuck key cannot keep the others down.
    func releaseModifiers() throws {
        defer { _ = modifiers.takeLatched() }
        try forEachCollectingFirstError(modifiers.pressed.reversed(), release)
    }

    // MARK: - Fn
    /// Holds Fn down. Does nothing while Fn is already held, physically or by Tastko.
    func pressFunction() throws {
        guard !modifiers.isFunctionHeld, !physicalFlags().contains(.function) else { return }
        try post(.function, keyDown: true, committing: modifiers.holdingFunction(true))
    }

    func releaseFunction() throws {
        guard modifiers.isFunctionHeld else { return }
        try post(.function, keyDown: false, committing: modifiers.holdingFunction(false))
    }

    // MARK: - Caps Lock
    /// Reports a Caps Lock toggle that the system state already applied.
    func postCapsLock(isEnabled: Bool) throws {
        let flags = modifiers.flags(physical: physicalFlags())
            .subtracting(.capsLock).union(isEnabled ? .capsLock : [])
        try poster.postKey(.capsLock, modifiers: flags, keyDown: true)
        try poster.postKey(.capsLock, modifiers: flags, keyDown: false)
    }

    // MARK: - Chord Modifiers
    /// Presses the modifier keys a stroke needs and returns the ones to release after it.
    ///
    /// Latched modifiers whose flags the stroke carries transfer to it; the rest are
    /// released. Command, Control, and Option flags without a held key get a real
    /// key press, because hotkey handlers ignore a key event that only carries flags.
    private func pressModifiers(for stroke: KeyStroke) throws -> [ModifierKey] {
        let claimed = modifiers.takeLatched().filter {
            stroke.modifiers.isSuperset(of: $0.modifiers)
        }
        for modifier in modifiers.pressed.reversed() where !claimed.contains(modifier) {
            try release(modifier)
        }
        let owned = claimed + chordModifiers(for: stroke, claimed: claimed)
        do {
            for modifier in owned { try press(modifier) }
        }
        catch {
            releaseBestEffort(owned)
            throw error
        }
        return owned
    }

    private func chordModifiers(for stroke: KeyStroke, claimed: [ModifierKey]) -> [ModifierKey] {
        guard !stroke.modifiers.isDisjoint(with: [.command, .control, .option]) else { return [] }
        let covered = modifiers.flags(physical: physicalFlags()).union(claimed.flags)
        let order: [ModifierKey] = [.leftControl, .leftOption, .leftShift, .leftCommand]
        return order.filter {
            stroke.modifiers.isSuperset(of: $0.modifiers) && covered.isDisjoint(with: $0.modifiers)
        }
    }

    // MARK: - Modifier Transitions
    private func press(_ modifier: ModifierKey) throws {
        guard !modifiers.isEngaged(modifier, physical: physicalFlags()) else { return }
        try post(modifier.key, keyDown: true, committing: modifiers.pressing(modifier))
    }

    private func release(_ modifier: ModifierKey) throws {
        guard modifiers.pressed.contains(modifier) else { return }
        try post(modifier.key, keyDown: false, committing: modifiers.releasing(modifier))
    }

    private func release(_ owned: [ModifierKey]) throws {
        for modifier in owned.reversed() { try release(modifier) }
    }

    private func releaseBestEffort(_ owned: [ModifierKey]) {
        for modifier in owned.reversed() { try? release(modifier) }
    }

    /// Posts a modifier event with the next state's flags, then commits that state.
    private func post(_ key: Key, keyDown: Bool, committing next: ModifierLedger) throws {
        try poster.postKey(key, modifiers: next.flags(physical: physicalFlags()), keyDown: keyDown)
        modifiers = next
    }
}

// MARK: - Error Collection
/// Runs every step, then rethrows the first failure.
@MainActor
private func forEachCollectingFirstError<S: Sequence>(
    _ elements: S,
    _ body: (S.Element) throws -> Void
) throws {
    var firstError: (any Error)?
    for element in elements {
        do { try body(element) }
        catch { firstError = firstError ?? error }
    }
    if let firstError { throw firstError }
}
