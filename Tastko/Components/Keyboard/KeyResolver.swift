// MARK: - ResolvedKey
/// What a panel button shows and sends for the current keyboard state.
nonisolated struct ResolvedKey: Equatable {
    let title: String
    let secondaryTitle: String?
    let leftClickAction: KeyAction
    let rightClickAction: KeyAction
    var isDeadKey = false

    // MARK: - Actions
    func action(for trigger: KeyActionTrigger) -> KeyAction {
        switch trigger {
        case .leftClick: leftClickAction
        case .rightClick: rightClickAction
        }
    }
}

// MARK: - KeyResolutionContext
/// The keyboard state a key resolves against.
struct KeyResolutionContext {
    var language: KeyboardLanguageContext
    var labels: KeyboardLayoutTranslator
    var latchedModifiers: Set<ModifierKey>
    var heldModifiers: Set<ModifierKey>
    var isCapsLockEnabled: Bool
}

// MARK: - KeyResolver
/// Resolves a panel button in two steps: the language layout picks the base key,
/// then latched, held, and Caps Lock state pick its labels and final keystrokes.
enum KeyResolver {
    // MARK: - Resolution
    static func resolve(_ button: PanelEditorButton, in context: KeyResolutionContext)
        -> ResolvedKey
    {
        let base = LanguageAwareKeyResolver.presentation(
            title: button.title,
            secondaryTitle: button.secondaryTitle ?? "",
            leftClickAction: button.primaryAction,
            rightClickAction: button.secondaryAction,
            languageContext: context.language
        )
        return ModifierAwareKeyResolver.presentation(
            from: base,
            translator: context.labels,
            latchedModifiers: context.latchedModifiers,
            physicalModifiers: context.heldModifiers,
            isCapsLockEnabled: context.isCapsLockEnabled
        )
    }
}
