// MARK: - ModifierAwareKeyResolver
@MainActor
enum ModifierAwareKeyResolver {
    // MARK: - Presentation
    static func presentation(
        from base: ResolvedKey,
        translator: KeyboardLayoutTranslator,
        latchedModifiers: Set<ModifierKey>,
        physicalModifiers: Set<ModifierKey>,
        isCapsLockEnabled: Bool
    ) -> ResolvedKey {
        let shiftedAction = shiftedAction(for: base)

        // MARK: - Action Resolution
        func action(_ trigger: KeyActionTrigger, secondaryAction: KeyAction) -> KeyAction {
            KeyActionResolver.action(
                for: trigger,
                primaryAction: base.leftClickAction,
                secondaryAction: secondaryAction,
                latchedModifiers: latchedModifiers,
                physicalModifiers: physicalModifiers,
                isCapsLockEnabled: isCapsLockEnabled,
                primaryTitle: base.title
            )
        }

        let primaryAction = action(
            .leftClick,
            secondaryAction: shiftedAction ?? base.rightClickAction
        )
        if let shiftedAction, case .keyStroke(let primaryStroke) = primaryAction,
            let primaryLabel = translator.label(for: primaryStroke)
        {
            let secondaryAction = action(.rightClick, secondaryAction: shiftedAction)
            let secondaryTitle: String?
            if case .keyStroke(let stroke) = secondaryAction,
                let label = translator.label(for: stroke),
                label.title != primaryLabel.title,
                primaryStroke.modifiers.contains(.option)
                    || label.title.lowercased() != primaryLabel.title.lowercased()
            {
                secondaryTitle = label.title
            }
            else {
                secondaryTitle = nil
            }
            return ResolvedKey(
                title: primaryLabel.title,
                secondaryTitle: secondaryTitle,
                leftClickAction: primaryAction,
                rightClickAction: secondaryAction,
                isDeadKey: primaryLabel.isDeadKey
            )
        }

        return ResolvedKey(
            title: base.title,
            secondaryTitle: base.secondaryTitle,
            leftClickAction: primaryAction,
            rightClickAction: action(.rightClick, secondaryAction: base.rightClickAction),
            isDeadKey: base.isDeadKey
        )
    }

    // MARK: - Native Character Keys
    private static func shiftedAction(for presentation: ResolvedKey) -> KeyAction? {
        guard case .keyStroke(let stroke) = presentation.leftClickAction,
            stroke.modifiers.isEmpty, KeyboardLayoutTranslator.isPrintable(stroke.key)
        else { return nil }
        let shifted = KeyAction.keyStroke(KeyStroke(stroke.key, modifiers: [.shift]))
        return presentation.rightClickAction.isNone || presentation.rightClickAction == shifted
            ? shifted : nil
    }
}
