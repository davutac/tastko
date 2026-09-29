import Foundation

// MARK: - PredictionContext
struct PredictionContext: Equatable {
    let target: FocusedKeyboardTarget
    let value: FocusedTextValue
    let input: PredictionInput
    var source: Source = .accessibility

    enum Source: Equatable {
        case accessibility
        case typingSession(UUID, revision: Int)
    }

    // MARK: - Session Identity
    func hasSameSession(as other: Self) -> Bool {
        guard target.hasSameFocus(as: other.target) else { return false }
        switch (source, other.source) {
        case (.accessibility, .accessibility): return true
        case (.typingSession(let lhs, _), .typingSession(let rhs, _)): return lhs == rhs
        default: return false
        }
    }

    /// Whether words shown for `other` still apply here. Words for deleted text do not
    /// carry over to an emptied field, which gets its own starter words.
    func continuesPresentation(of other: Self) -> Bool {
        hasSameSession(as: other) && (!input.context.isEmpty || other.input.context.isEmpty)
    }

    // MARK: - Conservative Fallback Acceptance
    func acceptance(for word: String) -> PredictionInsertion? {
        if case .typingSession = source {
            guard input.validated([word]).first != nil,
                let insertion = input.acceptance(for: word), insertion.deleteBackwardCount == 0
            else { return nil }
            return insertion
        }
        return input.acceptance(for: word)
    }

    // MARK: - Snapshot Identity
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.target.hasSameFocus(as: rhs.target)
            && lhs.value == rhs.value && lhs.input == rhs.input && lhs.source == rhs.source
    }
}

// MARK: - PredictionChoice
struct PredictionChoice {
    let word: String
    let context: PredictionContext
}
