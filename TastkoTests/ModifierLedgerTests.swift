import Testing

@testable import Tastko

// MARK: - ModifierLedgerTests
struct ModifierLedgerTests {
    // MARK: - Flags
    @Test func flagsCombinePhysicalFnAndPressedModifiers() {
        let ledger = ModifierLedger()
            .pressing(.leftCommand)
            .pressing(.rightShift)
            .holdingFunction(true)
        #expect(ledger.flags(physical: [.capsLock]) == [.command, .shift, .function, .capsLock])
        #expect(ledger.heldFlags(physical: [.option]) == [.option, .function])
    }

    @Test func transitionsDescribeTheStateAfterTheEvent() {
        let ledger = ModifierLedger().pressing(.leftShift)
        #expect(ledger.pressing(.leftCommand).flags(physical: []) == [.shift, .command])
        #expect(ledger.releasing(.leftShift).flags(physical: []) == [])
        #expect(ledger.holdingFunction(true).holdingFunction(false) == ledger)
    }

    @Test func pressingTwiceKeepsOneEntryInPressOrder() {
        let ledger = ModifierLedger()
            .pressing(.leftShift)
            .pressing(.leftCommand)
            .pressing(.leftShift)
        #expect(ledger.pressed == [.leftShift, .leftCommand])
    }

    // MARK: - Engagement
    @Test func modifierIsEngagedWhenPressedOrItsFlagIsHeld() {
        let ledger = ModifierLedger().pressing(.leftShift).holdingFunction(true)
        #expect(ledger.isEngaged(.leftShift, physical: []))
        #expect(ledger.isEngaged(.leftOption, physical: [.option]))
        #expect(ledger.isEngaged(.function, physical: []))
        #expect(!ledger.isEngaged(.leftCommand, physical: [.shift]))
    }

    // MARK: - Latches
    @Test func takingLatchesClearsThemButKeepsTheirKeysPressed() {
        var ledger = ModifierLedger().pressing(.leftCommand).pressing(.leftShift)
        ledger.latch(.leftCommand)
        ledger.latch(.leftShift)
        ledger.latch(.leftCommand)
        #expect(ledger.takeLatched() == [.leftCommand, .leftShift])
        #expect(ledger.latched.isEmpty)
        #expect(ledger.pressed == [.leftCommand, .leftShift])
    }

    @Test func unlatchRemovesOnlyThatModifier() {
        var ledger = ModifierLedger()
        ledger.latch(.leftCommand)
        ledger.latch(.leftShift)
        ledger.unlatch(.leftCommand)
        #expect(ledger.latched == [.leftShift])
    }
}
