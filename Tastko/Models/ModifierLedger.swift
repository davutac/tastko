// MARK: - ModifierLedger
/// The modifier keys Tastko holds down itself, and the flags they put into effect.
///
/// A modifier transition event carries the flags of the state after it, so a key
/// down includes its own flag and a key up omits it. Compute the next ledger,
/// post its flags, and commit it only when posting succeeds.
nonisolated struct ModifierLedger: Equatable, Sendable {
    /// Modifier keys pressed by Tastko and not released yet, in press order.
    private(set) var pressed: [ModifierKey] = []
    /// One-shot modifiers that apply to the next key, in toggle order.
    private(set) var latched: [ModifierKey] = []
    /// Whether Tastko holds the Fn key down.
    private(set) var isFunctionHeld = false

    // MARK: - Flags
    /// Flags in effect: physical flags, Tastko's Fn hold, and every pressed modifier.
    func flags(physical: KeyModifiers) -> KeyModifiers {
        pressed.reduce(heldFlags(physical: physical)) { $0.union($1.modifiers) }
    }

    /// Flags held outside the pressed modifier keys: physical keys and Tastko's Fn hold.
    func heldFlags(physical: KeyModifiers) -> KeyModifiers {
        physical.union(isFunctionHeld ? .function : [])
    }

    /// Whether posting the modifier key would change nothing.
    func isEngaged(_ modifier: ModifierKey, physical: KeyModifiers) -> Bool {
        pressed.contains(modifier)
            || !heldFlags(physical: physical).isDisjoint(with: modifier.modifiers)
    }

    // MARK: - Transitions
    func pressing(_ modifier: ModifierKey) -> ModifierLedger {
        var next = self
        if !next.pressed.contains(modifier) { next.pressed.append(modifier) }
        return next
    }

    func releasing(_ modifier: ModifierKey) -> ModifierLedger {
        var next = self
        next.pressed.removeAll { $0 == modifier }
        return next
    }

    func holdingFunction(_ isHeld: Bool) -> ModifierLedger {
        var next = self
        next.isFunctionHeld = isHeld
        return next
    }

    // MARK: - Latches
    mutating func latch(_ modifier: ModifierKey) {
        if !latched.contains(modifier) { latched.append(modifier) }
    }

    mutating func unlatch(_ modifier: ModifierKey) {
        latched.removeAll { $0 == modifier }
    }

    /// Clears every latch and returns the latched modifiers. Their keys stay pressed.
    mutating func takeLatched() -> [ModifierKey] {
        defer { latched.removeAll() }
        return latched
    }
}

// MARK: - Modifier Flags
extension Sequence where Element == ModifierKey {
    nonisolated var flags: KeyModifiers {
        reduce([]) { $0.union($1.modifiers) }
    }
}
