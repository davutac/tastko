// MARK: - Prediction Text Coordinates
nonisolated enum PredictionTextCoordinates {
    // MARK: - AX Range to AXValue Mapping
    static func selection(
        in text: String,
        range: AccessibilityTextRange,
        textForRange: (AccessibilityTextRange) -> String?
    ) -> AccessibilityTextRange? {
        guard range.isInsertionPoint, range.location >= 0,
            text.contains(where: \.isNewline)
        else { return range }

        // Native fields use AXValue coordinates. Some web editors instead omit
        // paragraph breaks in AXStringForRange and AXSelectedTextRange.
        let fullText = textForRange(AccessibilityTextRange(location: 0, length: text.utf16.count))
        if fullText == text { return range }
        let rangeText = text.filter { !$0.isNewline }
        let reportedText =
            fullText
            ?? textForRange(
                AccessibilityTextRange(location: 0, length: rangeText.utf16.count)
            )
        guard reportedText == rangeText else { return range }

        var rangeOffset = 0
        var valueOffset = 0
        for character in text {
            if rangeOffset == range.location {
                // Both sides of an omitted newline share one AX offset. Without
                // cursor affinity there is no safe way to pick either side.
                guard !character.isNewline else { return nil }
                return AccessibilityTextRange(location: valueOffset, length: 0)
            }
            let width = character.utf16.count
            valueOffset += width
            if !character.isNewline { rangeOffset += width }
        }
        guard rangeOffset == range.location else { return nil }
        return AccessibilityTextRange(location: valueOffset, length: 0)
    }
}
