// MARK: - PredictionSpace
struct PredictionSpace {
    let before: PredictionContext
    /// The field text up to the cursor once the accepted word and its space land.
    let expectedText: String
    /// The text after the cursor, which the accepted word must not change.
    let followingText: String
    var awaitingInsertion = true

    // MARK: - Accepted Prediction
    init?(insertion: PredictionInsertion, context: PredictionContext) {
        guard context.source == .accessibility, context.input.isAtLineEnd,
            insertion.text.hasSuffix(" "),
            let text = context.value.text,
            let location = context.value.selectedRange?.location,
            let cursor = String.Index(utf16Offset: location, in: text).samePosition(in: text)
        else { return nil }
        before = context
        expectedText = String(text[..<cursor].dropLast(insertion.deleteBackwardCount)) + insertion.text
        followingText = String(text[cursor...])
    }

    // MARK: - Field Comparison
    /// Whether the field shows the accepted word and its space, and nothing more.
    func isInserted(in context: PredictionContext) -> Bool {
        typedAfterSpace(in: context) == ""
    }

    /// The text typed right after the automatic space, when nothing else changed.
    func typedAfterSpace(in context: PredictionContext) -> String? {
        guard let text = context.value.text,
            text.count >= expectedText.count + followingText.count,
            text.hasPrefix(expectedText), text.hasSuffix(followingText)
        else { return nil }
        let typed = String(text.dropFirst(expectedText.count).dropLast(followingText.count))
        let cursor = (expectedText + typed).utf16.count
        guard context.value.selectedRange == AccessibilityTextRange(location: cursor, length: 0)
        else { return nil }
        return typed
    }
}
