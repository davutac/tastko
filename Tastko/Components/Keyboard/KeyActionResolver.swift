import Foundation

// MARK: - KeyActionTrigger
nonisolated enum KeyActionTrigger: Hashable, Sendable {
    case leftClick
    case rightClick
}

// MARK: - KeyActionResolver
nonisolated enum KeyActionResolver {
    // MARK: - Action
    static func action(
        for trigger: KeyActionTrigger,
        primaryAction: KeyAction,
        secondaryAction: KeyAction,
        latchedModifiers: Set<ModifierKey>,
        physicalModifiers: Set<ModifierKey> = [],
        isCapsLockEnabled: Bool = false,
        primaryTitle: String = ""
    ) -> KeyAction {
        if primaryAction.isCapsLock {
            return primaryAction
        }

        let effectiveModifiers = latchedModifiers.union(physicalModifiers)
        let modifiedPrimary = primaryAction.applying(effectiveModifiers)
        if isCapsLockEnabled, !modifiedPrimary.isKeyboardShortcut {
            switch modifiedPrimary {
            case .text(let text):
                return .text(trigger == .rightClick ? text.lowercased() : text.uppercased())
            case .keyStroke(let stroke) where isLetter(stroke.key, title: primaryTitle):
                var flags = stroke.modifiers
                flags.subtract([.shift, .capsLock])
                if trigger == .leftClick {
                    flags.insert(.capsLock)
                }
                return .keyStroke(KeyStroke(stroke.key, modifiers: flags))
            default:
                break
            }
        }

        let action =
            switch trigger {
            case .rightClick:
                secondaryAction
            case .leftClick:
                leftClickAction(
                    primaryAction: primaryAction,
                    secondaryAction: secondaryAction,
                    latchedModifiers: effectiveModifiers
                )
            }

        let resolved = action.applying(effectiveModifiers)
        if isCapsLockEnabled, case .keyStroke(let stroke) = resolved,
            stroke.modifiers.contains(.option),
            stroke.modifiers.intersection([.command, .control, .function]).isEmpty
        {
            return .keyStroke(KeyStroke(stroke.key, modifiers: stroke.modifiers.union(.capsLock)))
        }
        return resolved
    }

    // MARK: - Letter Keys
    private static func isLetter(_ key: Key, title: String) -> Bool {
        if title.count == 1 {
            return title.uppercased() != title.lowercased()
        }

        switch key {
        case .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m,
            .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z:
            return true
        default:
            return false
        }
    }

    // MARK: - Shifted Actions
    private static func leftClickAction(
        primaryAction: KeyAction,
        secondaryAction: KeyAction,
        latchedModifiers: Set<ModifierKey>
    ) -> KeyAction {
        guard !primaryAction.isModifier else {
            return primaryAction
        }

        guard hasActiveShift(latchedModifiers), !secondaryAction.isNone else {
            return primaryAction
        }

        return secondaryAction
    }

    // MARK: - Shift State
    private static func hasActiveShift(_ modifiers: Set<ModifierKey>) -> Bool {
        modifiers.contains { modifier in
            modifier.modifiers.contains(.shift)
        }
    }
}

extension KeyAction {
    // MARK: - Shortcuts
    fileprivate nonisolated var isKeyboardShortcut: Bool {
        guard case .keyStroke(let stroke) = self else { return false }
        return !stroke.modifiers.intersection([.command, .control, .option, .function]).isEmpty
    }

    // MARK: - Modifiers
    fileprivate nonisolated func applying(_ modifiers: Set<ModifierKey>) -> KeyAction {
        guard case .keyStroke(let stroke) = self else {
            return self
        }

        let modifierFlags = modifiers.reduce(into: KeyModifiers(rawValue: 0)) { flags, modifier in
            flags.formUnion(modifier.modifiers)
        }

        return .keyStroke(
            KeyStroke(
                stroke.key,
                modifiers: stroke.modifiers.union(modifierFlags)
            )
        )
    }
}

// MARK: - KeyAction State
extension KeyAction {
    nonisolated var isNone: Bool {
        guard case .none = self else {
            return false
        }

        return true
    }

    nonisolated var isModifier: Bool {
        switch self {
        case .modifier:
            true
        default:
            isCapsLock
        }
    }

    nonisolated var isRepeatable: Bool {
        switch self {
        case .none, .modifier(_), .cycleKeyboardLanguage, .toggleFunctionToolbar:
            false
        case .text(let text):
            !text.isEmpty
        case .keyStroke(let stroke):
            stroke.key != .capsLock
        }
    }

    nonisolated var isCapsLock: Bool {
        guard case .keyStroke(let stroke) = self else { return false }
        return stroke.key == .capsLock
    }
}
