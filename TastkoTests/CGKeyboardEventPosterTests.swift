import CoreGraphics
import Testing

@testable import Tastko

// MARK: - CGKeyboardEventPosterTests
@MainActor
struct CGKeyboardEventPosterTests {
    // These tests only create events. Never call postKey, postKeyRepeat, or CGEvent.post.

    // MARK: - Function Events
    @Test func functionTransitionsAreTaggedFlagsChangedEvents() throws {
        let poster = CGKeyboardEventPoster()
        let down = try poster.keyEvent(.function, modifiers: [.command, .function], keyDown: true)
        let up = try poster.keyEvent(.function, modifiers: [.command], keyDown: false)

        #expect(down.type == .flagsChanged)
        #expect(up.type == .flagsChanged)
        #expect(down.flags == [.maskCommand, .maskSecondaryFn])
        #expect(up.flags == [.maskCommand])
        for event in [down, up] {
            #expect(event.getIntegerValueField(.keyboardEventKeycode) == 0x3F)
            #expect(event.getIntegerValueField(.keyboardEventAutorepeat) == 0)
            #expect(
                event.getIntegerValueField(.eventSourceUserData)
                    == CGKeyboardEventPoster.predictionEventTag
            )
        }
    }

    // MARK: - Modifier Events
    @Test(arguments: [
        (Key.leftShift, KeyModifiers.shift, CGEventFlags.maskShift, Int64(0x38)),
        (.rightShift, .shift, .maskShift, 0x3C),
        (.leftCommand, .command, .maskCommand, 0x37),
        (.rightCommand, .command, .maskCommand, 0x36),
        (.leftOption, .option, .maskAlternate, 0x3A),
        (.rightOption, .option, .maskAlternate, 0x3D),
        (.leftControl, .control, .maskControl, 0x3B),
        (.rightControl, .control, .maskControl, 0x3E),
        (.function, .function, .maskSecondaryFn, 0x3F),
        (.capsLock, .capsLock, .maskAlphaShift, 0x39),
    ])
    func modifierTransitionsPreserveKeycodeFlagsAndTag(
        key: Key,
        modifiers: KeyModifiers,
        flags: CGEventFlags,
        keycode: Int64
    ) throws {
        let poster = CGKeyboardEventPoster()
        let down = try poster.keyEvent(key, modifiers: modifiers, keyDown: true)
        let up = try poster.keyEvent(key, modifiers: [], keyDown: false)

        #expect(down.flags == flags)
        #expect(up.flags.isEmpty)
        for event in [down, up] {
            #expect(event.type == .flagsChanged)
            #expect(event.getIntegerValueField(.keyboardEventKeycode) == keycode)
            #expect(event.getIntegerValueField(.keyboardEventAutorepeat) == 0)
            #expect(
                event.getIntegerValueField(.eventSourceUserData)
                    == CGKeyboardEventPoster.predictionEventTag
            )
        }
    }

    // MARK: - Ordinary Events
    @Test(arguments: [Key.a, .delete, .leftArrow, .f1], [true, false])
    func ordinaryEventsKeepDownUpTypeKeycodeFlagsAndTag(key: Key, keyDown: Bool) throws {
        let event = try CGKeyboardEventPoster().keyEvent(
            key,
            modifiers: [
                .command, .shift, .option, .control, .capsLock, .function, .numericPad, .help,
            ],
            keyDown: keyDown
        )

        #expect(event.type == (keyDown ? CGEventType.keyDown : .keyUp))
        #expect(event.getIntegerValueField(.keyboardEventKeycode) == Int64(key.rawValue))
        #expect(
            event.flags == [
                .maskCommand, .maskShift, .maskAlternate, .maskControl,
                .maskAlphaShift, .maskSecondaryFn, .maskNumericPad, .maskHelp,
            ]
        )
        #expect(event.getIntegerValueField(.keyboardEventAutorepeat) == 0)
        #expect(
            event.getIntegerValueField(.eventSourceUserData)
                == CGKeyboardEventPoster.predictionEventTag
        )
    }

    // MARK: - Text Events
    @Test func longTextIsTypedInEventSizedChunksThatReassembleIt() throws {
        // The family emoji is 11 UTF-16 units and lands across the 20-unit boundary.
        let text = "Thanks for the update 👨‍👩‍👧‍👦 see you tomorrow at the café."
        let events = try CGKeyboardEventPoster().textEvents(text)
        let strings = events.map(Self.unicodeString)

        #expect(events.count.isMultiple(of: 2))
        #expect(events.count > 2)
        #expect(
            events.enumerated().allSatisfy { $1.type == ($0.isMultiple(of: 2) ? .keyDown : .keyUp) }
        )
        #expect(
            stride(from: 0, to: strings.count, by: 2).allSatisfy { strings[$0] == strings[$0 + 1] }
        )
        #expect(stride(from: 0, to: strings.count, by: 2).map { strings[$0] }.joined() == text)
        #expect(
            strings.allSatisfy {
                $0.utf16.count <= CGKeyboardEventPoster.maximumUnicodeStringLength
            }
        )
        #expect(strings.contains { $0.contains("👨‍👩‍👧‍👦") })
        #expect(
            events.allSatisfy {
                $0.getIntegerValueField(.eventSourceUserData)
                    == CGKeyboardEventPoster.predictionEventTag
            }
        )
    }

    @Test func chunksNeverSplitACharacter() {
        let oversized = String(repeating: "e\u{301}", count: 15)
        #expect(CGKeyboardEventPoster.unicodeChunks("") == [])
        #expect(CGKeyboardEventPoster.unicodeChunks("short") == ["short"])
        #expect(CGKeyboardEventPoster.unicodeChunks(oversized).joined() == oversized)
        #expect(CGKeyboardEventPoster.unicodeChunks(oversized).map(\.utf16.count) == [20, 10])
    }

    private static func unicodeString(_ event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 64)
        event.keyboardGetUnicodeString(
            maxStringLength: buffer.count,
            actualStringLength: &length,
            unicodeString: &buffer
        )
        return String(decoding: buffer.prefix(length), as: UTF16.self)
    }

    // MARK: - Repeat Events
    @Test func repeatIsTaggedKeyDownAndDoesNotLeakIntoFollowingEvents() throws {
        let poster = CGKeyboardEventPoster()
        let initial = try poster.keyEvent(.delete, modifiers: [.option], keyDown: true)
        let repeated = try poster.keyEvent(
            .delete,
            modifiers: [.option],
            keyDown: true,
            isRepeat: true
        )
        let up = try poster.keyEvent(.delete, modifiers: [.option], keyDown: false)
        let next = try poster.keyEvent(.delete, modifiers: [.option], keyDown: true)

        #expect(initial.type == .keyDown)
        #expect(repeated.type == .keyDown)
        #expect(up.type == .keyUp)
        #expect(next.type == .keyDown)
        #expect(initial.getIntegerValueField(.keyboardEventAutorepeat) == 0)
        #expect(repeated.getIntegerValueField(.keyboardEventAutorepeat) == 1)
        #expect(up.getIntegerValueField(.keyboardEventAutorepeat) == 0)
        #expect(next.getIntegerValueField(.keyboardEventAutorepeat) == 0)
        for event in [initial, repeated, up, next] {
            #expect(event.getIntegerValueField(.keyboardEventKeycode) == 0x33)
            #expect(event.flags == [.maskAlternate])
            #expect(
                event.getIntegerValueField(.eventSourceUserData)
                    == CGKeyboardEventPoster.predictionEventTag
            )
        }
    }
}
