import CoreGraphics

// MARK: - CGKeyboardEventPoster
struct CGKeyboardEventPoster: KeyboardEventPosting {
    // Distinguish our posted events from physical or other applications' input.
    static let predictionEventTag: Int64 = 0x41_6962_6F61_7264
    private let source = CGEventSource(stateID: .combinedSessionState)

    // MARK: - System-Focus Text
    func postTextToSystemFocus(_ text: String) throws {
        let down = try unicodeEvent(text, keyDown: true)
        let up = try unicodeEvent(text, keyDown: false)
        down.flags = []
        up.flags = []
        post(down, keyDown: true)
        post(up, keyDown: false)
    }

    func postText(_ text: String, to target: FocusedKeyboardTarget) throws {
        let keyDown = try unicodeEvent(text, keyDown: true)
        let keyUp = try unicodeEvent(text, keyDown: false)

        post(keyDown, keyDown: true, to: target.processIdentifier)
        post(keyUp, keyDown: false, to: target.processIdentifier)
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
        if !text.isEmpty {
            events.append(try unicodeEvent(text, keyDown: true))
            events.append(try unicodeEvent(text, keyDown: false))
        }
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
            PhysicalKeyboardState.shared.recordPostedKey(key, isDown: keyDown)
        }
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
