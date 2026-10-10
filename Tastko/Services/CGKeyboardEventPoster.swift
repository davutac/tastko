import CoreGraphics

// MARK: - CGKeyboardEventPoster
struct CGKeyboardEventPoster: KeyboardEventPosting {
    // Distinguish our posted events from physical or other applications' input.
    static let predictionEventTag: Int64 = 0x41_6962_6F61_7264
    private let source = CGEventSource(stateID: .combinedSessionState)
    /// Masks posted keys so physical-key feedback ignores Tastko's own events.
    private let physicalKeyboard: PhysicalKeyboardState

    // MARK: - Initialization
    init(physicalKeyboard: PhysicalKeyboardState? = nil) {
        self.physicalKeyboard = physicalKeyboard ?? .shared
    }

    // MARK: - System-Focus Text
    func postTextToSystemFocus(_ text: String) throws {
        for event in try textEvents(text) {
            event.flags = []
            post(event, keyDown: event.type == .keyDown)
        }
    }

    func postText(_ text: String, to target: FocusedKeyboardTarget) throws {
        for event in try textEvents(text) {
            post(event, keyDown: event.type == .keyDown, to: target.processIdentifier)
        }
    }

    // MARK: - Prediction Replacement
    func replacePrefix(_ count: Int, with text: String, to target: FocusedKeyboardTarget) throws {
        // Prepare every event before changing text, so allocation failure cannot
        // leave a partially deleted prefix. Deliver all events to the captured app.
        var events: [CGEvent] = []
        for _ in 0..<count {
            for down in [true, false] {
                guard
                    let event = CGEvent(
                        keyboardEventSource: source,
                        virtualKey: 0x33,
                        keyDown: down
                    )
                else { throw KeyboardServiceError.eventCreationFailed }
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: Self.predictionEventTag)
                events.append(event)
            }
        }
        events += try textEvents(text)
        for event in events {
            event.flags = []
            post(event, keyDown: event.type == .keyDown, to: target.processIdentifier)
        }
    }

    // MARK: - Key Delivery
    func postKey(
        _ key: Key,
        modifiers: KeyModifiers,
        keyDown: Bool
    ) throws {
        post(try keyEvent(key, modifiers: modifiers, keyDown: keyDown), keyDown: keyDown)
    }

    // MARK: - Repeat Delivery
    func postKeyRepeat(_ key: Key, modifiers: KeyModifiers) throws {
        post(
            try keyEvent(key, modifiers: modifiers, keyDown: true, isRepeat: true),
            keyDown: true
        )
    }

    // MARK: - Tracked Delivery
    private func post(_ event: CGEvent, keyDown: Bool, to processIdentifier: pid_t? = nil) {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if let key = Key(rawValue: keyCode) {
            physicalKeyboard.recordPostedKey(key, isDown: keyDown)
        }
        physicalKeyboard.recordPostedFlags(event.flags)
        if let processIdentifier {
            event.postToPid(processIdentifier)
        }
        else {
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Key Events
    func keyEvent(
        _ key: Key,
        modifiers: KeyModifiers,
        keyDown: Bool,
        isRepeat: Bool = false
    ) throws -> CGEvent {
        guard
            let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: key.cgKeyCode,
                keyDown: keyDown
            )
        else {
            throw KeyboardServiceError.eventCreationFailed
        }
        if key == .capsLock || ModifierKey.allCases.contains(where: { $0.key == key }) {
            event.type = .flagsChanged
        }
        event.flags = modifiers.cgEventFlags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: isRepeat ? 1 : 0)
        event.setIntegerValueField(.eventSourceUserData, value: Self.predictionEventTag)
        return event
    }

    // MARK: - Text Events
    /// Receivers can read at most this many UTF-16 units from one keyboard event.
    static let maximumUnicodeStringLength = 20

    /// Key down and up events that type `text`, created before any is posted so a
    /// failure cannot leave the text partially typed.
    func textEvents(_ text: String) throws -> [CGEvent] {
        try Self.unicodeChunks(text).flatMap { chunk in
            [try unicodeEvent(chunk, keyDown: true), try unicodeEvent(chunk, keyDown: false)]
        }
    }

    /// Splits text into event-sized chunks without splitting a character. A single
    /// character longer than the limit stays whole.
    static func unicodeChunks(_ text: String) -> [String] {
        var chunks: [String] = []
        var chunk = ""
        for character in text {
            if !chunk.isEmpty,
                chunk.utf16.count + character.utf16.count > maximumUnicodeStringLength
            {
                chunks.append(chunk)
                chunk = ""
            }
            chunk.append(character)
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        return chunks
    }

    // MARK: - Events
    private func unicodeEvent(_ text: String, keyDown: Bool) throws -> CGEvent {
        guard
            let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: keyDown
            )
        else {
            throw KeyboardServiceError.eventCreationFailed
        }

        let characters = Array(text.utf16)
        event.setIntegerValueField(.eventSourceUserData, value: Self.predictionEventTag)

        characters.withUnsafeBufferPointer { buffer in
            event.keyboardSetUnicodeString(
                stringLength: characters.count,
                unicodeString: buffer.baseAddress
            )
        }

        return event
    }
}
