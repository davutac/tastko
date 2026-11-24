// MARK: - SwipeAlternatives
/// A swiped word just inserted, and its other readings that the suggestion strip offers in its
/// place. Only a field Accessibility can read gets them: replacing the word deletes it first.
struct SwipeAlternatives {
    let before: PredictionContext
    let inserted: SwipedWordParts
    /// The other readings, best first.
    let readings: [String]
    /// The field text up to the cursor once the word lands.
    let expectedText: String
    /// The text after the cursor, which the word must not change.
    let followingText: String
    var awaitingInsertion = true

    // MARK: - Inserted Word
    /// `inserted`, put in at `context`'s cursor after deleting `deletedCount` characters.
    init?(
        inserted: SwipedWordParts,
        readings: [String],
        deletedCount: Int = 0,
        context: PredictionContext
    ) {
        guard context.source == .accessibility, !readings.isEmpty,
            let text = context.value.text,
            let location = context.value.selectedRange?.location,
            let cursor = String.Index(utf16Offset: location, in: text).samePosition(in: text)
        else { return nil }
        before = context
        self.inserted = inserted
        self.readings = readings
        expectedText = String(text[..<cursor].dropLast(deletedCount)) + inserted.text
        followingText = String(text[cursor...])
    }

    // MARK: - Field Comparison
    /// Whether the field shows the word where it went in, with the cursor right after it.
    func isShown(in context: PredictionContext) -> Bool {
        guard context.source == .accessibility,
            context.target.hasSameFocus(as: before.target),
            context.value.text == expectedText + followingText
        else { return false }
        return context.value.selectedRange
            == AccessibilityTextRange(location: expectedText.utf16.count, length: 0)
    }

    // MARK: - Replacement
    /// Puts `reading` in the word's place, with the same spaces around it.
    func replacement(with reading: String) -> PredictionInsertion {
        PredictionInsertion(
            text: inserted.replacingWord(with: reading).text,
            deleteBackwardCount: inserted.text.count
        )
    }

    /// The alternatives once `reading` replaced the word at `context`: the word it replaced
    /// comes first among them, so a second click can go back.
    func swapped(to reading: String, at context: PredictionContext) -> Self? {
        Self(
            inserted: inserted.replacingWord(with: reading),
            readings: [inserted.word] + readings.filter { $0 != reading },
            deletedCount: inserted.text.count,
            context: context
        )
    }
}
