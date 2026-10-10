import AppKit
import SwiftUI
import Testing

@testable import Tastko

// MARK: - PointerVisibilityPolicyTests
struct PointerVisibilityPolicyTests {
    private let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
    private let outside = CGPoint(x: 700, y: 400)
    private let corner = CGPoint(x: 1_439, y: 1)

    // MARK: - Sampling Schedule
    @Test func samplesFrequentlyOnlyWhileActiveOrDwelling() {
        var policy = PointerVisibilityPolicy()
        #expect(policy.needsFrequentSampling(at: 0))
        _ = sample(&policy, outside, at: 0)
        #expect(policy.needsFrequentSampling(at: 0.4))
        #expect(!policy.needsFrequentSampling(at: 0.6))
        _ = sample(&policy, outside, at: 5)
        #expect(!policy.needsFrequentSampling(at: 5))
        _ = sample(&policy, corner, at: 6)
        #expect(policy.needsFrequentSampling(at: 7))
        #expect(sample(&policy, corner, at: 7.5) == .toggle)
        #expect(!policy.needsFrequentSampling(at: 8))
    }

    @Test func inactivityDeadlineFollowsActivityAndClearsAfterHiding() {
        var policy = PointerVisibilityPolicy()
        _ = sample(&policy, outside, at: 0)
        #expect(policy.inactivityDeadline == PointerVisibilityPolicy.defaultInactivityDelay)
        _ = sample(&policy, CGPoint(x: 701, y: 400), at: 3)
        #expect(policy.inactivityDeadline == 3 + PointerVisibilityPolicy.defaultInactivityDelay)
        #expect(sample(&policy, CGPoint(x: 701, y: 400), at: 18) == .hideForInactivity)
        #expect(policy.inactivityDeadline == nil)
        _ = policy.update(
            location: outside,
            screenFrames: [screen],
            mouseButtonIsDown: false,
            time: 19,
            inactivityDelay: nil
        )
        #expect(policy.inactivityDeadline == nil)
    }

    // MARK: - Corner Dwell
    @Test func cornerRequiresDwellAndOnlyRearmsAfterLeaving() {
        var policy = PointerVisibilityPolicy()
        #expect(sample(&policy, outside, at: 0) == nil)
        #expect(sample(&policy, corner, at: 1) == .restoreFromInactivity)
        #expect(sample(&policy, corner, at: 2.49) == nil)
        #expect(sample(&policy, corner, at: 2.5) == .toggle)
        #expect(sample(&policy, CGPoint(x: 1_437, y: 3), at: 3) == .restoreFromInactivity)
        #expect(sample(&policy, corner, at: 30) == .restoreFromInactivity)
        #expect(sample(&policy, corner, at: 60) == nil)
        #expect(sample(&policy, outside, at: 61) == .restoreFromInactivity)
        #expect(sample(&policy, corner, at: 62) == .restoreFromInactivity)
        #expect(sample(&policy, corner, at: 63.5) == .toggle)
    }

    @Test func leavingEarlyCancelsDwell() {
        var policy = PointerVisibilityPolicy()
        _ = sample(&policy, outside, at: 0)
        _ = sample(&policy, corner, at: 1)
        _ = sample(&policy, outside, at: 2)
        _ = sample(&policy, corner, at: 2.1)
        #expect(sample(&policy, corner, at: 2.6) == nil)
        #expect(sample(&policy, corner, at: 3.6) == .toggle)
    }

    @Test func launchInsideCornerRequiresLeavingBeforeActivation() {
        var policy = PointerVisibilityPolicy()
        #expect(sample(&policy, corner, at: 0) == nil)
        #expect(sample(&policy, corner, at: 100) == nil)
        _ = sample(&policy, outside, at: 101)
        _ = sample(&policy, corner, at: 102)
        #expect(sample(&policy, corner, at: 103.5) == .toggle)
    }

    @Test(arguments: [
        CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
        CGRect(x: 200, y: -1_080, width: 1_920, height: 1_080),
        CGRect(x: 0, y: 900, width: 900, height: 1_440),
    ])
    func bottomRightUsesEachDisplaysAppKitCoordinates(_ secondary: CGRect) {
        var policy = PointerVisibilityPolicy()
        let frames = [screen, secondary]
        _ = policy.update(
            location: outside,
            screenFrames: frames,
            mouseButtonIsDown: false,
            time: 0
        )
        let point = CGPoint(x: secondary.maxX - 1, y: secondary.minY + 1)
        _ = policy.update(location: point, screenFrames: frames, mouseButtonIsDown: false, time: 1)
        #expect(
            policy.update(
                location: point,
                screenFrames: frames,
                mouseButtonIsDown: false,
                time: 2.5
            ) == .toggle
        )
    }

    @Test(arguments: [
        CGPoint(x: 1_439, y: 899), CGPoint(x: 1, y: 1),
        CGPoint(x: 1_433, y: 1), CGPoint(x: 1_439, y: 7),
        CGPoint(x: 1_441, y: 1), CGPoint(x: 1_439, y: -1),
    ])
    func otherCornersAndPositionsOutsideTheScreenDoNotTrigger(_ point: CGPoint) {
        var policy = PointerVisibilityPolicy()
        _ = sample(&policy, outside, at: 0)
        _ = sample(&policy, point, at: 1)
        #expect(sample(&policy, point, at: 3) == nil)
    }

    // MARK: - Countdown
    @Test func countdownTracksDwellAndDisappearsOnCancellationOrCompletion() {
        var policy = PointerVisibilityPolicy()
        _ = sample(&policy, outside, at: 0)
        _ = sample(&policy, corner, at: 1)
        #expect(policy.cornerProgress?.remaining == 1.5)
        #expect(policy.cornerProgress?.screenFrame == screen)
        _ = sample(&policy, corner, at: 1.75)
        #expect(policy.cornerProgress?.fraction == 0.5)
        #expect(policy.cornerProgress?.remaining == 0.75)
        _ = sample(&policy, outside, at: 2)
        #expect(policy.cornerProgress == nil)
        _ = sample(&policy, corner, at: 3)
        #expect(policy.cornerProgress?.remaining == 1.5)
        #expect(sample(&policy, corner, at: 4.5) == .toggle)
        #expect(policy.cornerProgress == nil)
        _ = sample(&policy, corner, at: 5)
        #expect(policy.cornerProgress == nil)
    }

    @Test func heldMouseCancelsCountdownAndReleaseStartsFreshDwell() {
        var policy = PointerVisibilityPolicy()
        _ = sample(&policy, outside, at: 0)
        _ = sample(&policy, corner, at: 1)
        _ = sample(&policy, corner, at: 2, held: true)
        #expect(policy.cornerProgress == nil)
        _ = sample(&policy, corner, at: 3)
        #expect(policy.cornerProgress?.remaining == 1.5)
    }

    // MARK: - Adjustable Dwell
    @Test(arguments: [0.5, 1.5, 3.0, 5.0])
    func countdownAndTriggerShareConfiguredDwell(_ dwell: TimeInterval) {
        var policy = PointerVisibilityPolicy()
        _ = sample(&policy, outside, at: 0, dwell: dwell)
        _ = sample(&policy, corner, at: 1, dwell: dwell)
        #expect(policy.cornerProgress?.remaining == dwell)
        _ = sample(&policy, corner, at: 1 + dwell / 2, dwell: dwell)
        #expect(policy.cornerProgress?.fraction == 0.5)
        #expect(policy.cornerProgress?.remaining == dwell / 2)
        #expect(sample(&policy, corner, at: 1 + dwell - 0.01, dwell: dwell) == nil)
        #expect(sample(&policy, corner, at: 1 + dwell, dwell: dwell) == .toggle)
    }

    @Test(arguments: [0.5, 5.0])
    func changingPendingDwellRestartsCountdown(_ newDwell: TimeInterval) {
        var policy = PointerVisibilityPolicy()
        _ = sample(&policy, outside, at: 0)
        _ = sample(&policy, corner, at: 1)
        _ = sample(&policy, corner, at: 2)
        #expect(sample(&policy, corner, at: 2.4, dwell: newDwell) == nil)
        #expect(policy.cornerProgress?.remaining == newDwell)
        #expect(policy.cornerProgress?.fraction == 0)
        #expect(sample(&policy, corner, at: 2.4 + newDwell - 0.01, dwell: newDwell) == nil)
        #expect(sample(&policy, corner, at: 2.4 + newDwell + 0.001, dwell: newDwell) == .toggle)
    }

    @Test func changingDwellAfterToggleDoesNotRearmTheCorner() {
        var policy = PointerVisibilityPolicy()
        _ = sample(&policy, outside, at: 0)
        _ = sample(&policy, corner, at: 1)
        #expect(sample(&policy, corner, at: 2.5) == .toggle)
        #expect(sample(&policy, corner, at: 3, dwell: 0.5) == nil)
        #expect(sample(&policy, corner, at: 30, dwell: 0.5) == nil)
        #expect(policy.cornerProgress == nil)
        _ = sample(&policy, outside, at: 31, dwell: 0.5)
        _ = sample(&policy, corner, at: 32, dwell: 0.5)
        #expect(sample(&policy, corner, at: 32.5, dwell: 0.5) == .toggle)
    }

    @Test(arguments: [Double.nan, .infinity, -1, 0, 100])
    func invalidStoredDwellRemainsBoundedAndCannotToggleImmediately(_ value: Double) {
        var policy = PointerVisibilityPolicy()
        _ = sample(&policy, outside, at: 0, dwell: value)
        #expect(sample(&policy, corner, at: 1, dwell: value) == .restoreFromInactivity)
        #expect(policy.cornerProgress?.fraction == 0)
        let expected = value.isFinite ? min(max(value, 0.5), 5) : 1.5
        #expect(policy.cornerProgress?.remaining == expected)
        #expect(sample(&policy, corner, at: 1 + expected, dwell: value) == .toggle)
    }

    // MARK: - Inactivity
    @Test func inactivityHidesOnceAfterFifteenSecondsAndMovementRestores() {
        var policy = PointerVisibilityPolicy()
        _ = sample(&policy, outside, at: 0)
        #expect(sample(&policy, outside, at: 14.99) == nil)
        #expect(sample(&policy, outside, at: 15) == .hideForInactivity)
        #expect(sample(&policy, outside, at: 60) == nil)
        let moved = CGPoint(x: 701, y: 400)
        #expect(sample(&policy, moved, at: 61) == .restoreFromInactivity)
        #expect(sample(&policy, moved, at: 75) == nil)
        #expect(sample(&policy, moved, at: 76) == .hideForInactivity)
    }

    @Test func heldButtonsPreventHidingAndRestartTheIdlePeriod() {
        var policy = PointerVisibilityPolicy()
        _ = sample(&policy, outside, at: 0)
        #expect(sample(&policy, outside, at: 30, held: true) == nil)
        #expect(sample(&policy, outside, at: 44) == nil)
        #expect(sample(&policy, outside, at: 45) == .hideForInactivity)
        _ = sample(&policy, corner, at: 46, held: true)
        #expect(sample(&policy, corner, at: 60, held: true) == nil)
        #expect(sample(&policy, corner, at: 61) == nil)
        #expect(sample(&policy, corner, at: 62.5) == .toggle)
    }

    @Test func disablingAutoHideCancelsInactivityAndRequestsRestoration() {
        var policy = PointerVisibilityPolicy()
        _ = sample(&policy, outside, at: 0)
        #expect(sample(&policy, outside, at: 15) == .hideForInactivity)
        #expect(sample(&policy, outside, at: 16, delay: nil) == .restoreFromInactivity)
        #expect(sample(&policy, outside, at: 100, delay: nil) == nil)
        _ = sample(&policy, corner, at: 101, delay: nil)
        #expect(sample(&policy, corner, at: 102.5, delay: nil) == .toggle)
    }

    @Test func enablingAndChangingDurationStartsAFreshIdlePeriod() {
        var policy = PointerVisibilityPolicy()
        _ = sample(&policy, outside, at: 0, delay: nil)
        #expect(sample(&policy, outside, at: 50, delay: 20) == nil)
        #expect(sample(&policy, outside, at: 69, delay: 20) == nil)
        #expect(sample(&policy, outside, at: 70, delay: 20) == .hideForInactivity)
        #expect(sample(&policy, outside, at: 71, delay: 5) == nil)
        #expect(sample(&policy, outside, at: 75.9, delay: 5) == nil)
        #expect(sample(&policy, outside, at: 76, delay: 5) == .hideForInactivity)
    }

    // MARK: - Sampling
    private func sample(
        _ policy: inout PointerVisibilityPolicy,
        _ location: CGPoint,
        at time: TimeInterval,
        held: Bool = false,
        delay: TimeInterval? = 15,
        dwell: TimeInterval = 1.5
    ) -> PointerVisibilityAction? {
        policy.update(
            location: location,
            screenFrames: [screen],
            mouseButtonIsDown: held,
            time: time,
            inactivityDelay: delay,
            cornerDwell: dwell
        )
    }
}

// MARK: - PointerVisibilityWindowTests
@MainActor
struct PointerVisibilityWindowTests {
    // MARK: - Corner Overlay
    @Test func cornerOverlayCannotTakeFocusOrInterceptThePointer() {
        let panel = HotCornerIndicatorPanel()
        defer { panel.close() }
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.ignoresMouseEvents)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
    }

    // MARK: - Keyboard Restoration
    @Test(arguments: [CGSize(width: 820, height: 350), CGSize(width: 96, height: 96)])
    func hideAndShowRestoreWindowGeometryWithoutTakingFocus(_ size: CGSize) throws {
        let controller = AlwaysOnTopWindowController()
        var frame = CGRect.zero
        let configuration = AlwaysOnTopWindowConfiguration(
            size: size,
            minSize: size,
            maxSize: size,
            origin: CGPoint(x: 100, y: 100),
            sizeDidChange: { frame.size = $0 },
            originDidChange: { frame.origin = $0 }
        )
        let originalWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let keyWindow = NSApp.keyWindow
        let mainWindow = NSApp.mainWindow
        defer {
            controller.hide()
            for window in NSApp.windows where !originalWindows.contains(ObjectIdentifier(window)) {
                window.close()
            }
        }
        controller.show(configuration: configuration) {
            Color.clear.frame(width: size.width, height: size.height)
        }
        let originalFrame = frame
        #expect(controller.isVisible)
        controller.hide()
        #expect(!controller.isVisible)
        controller.show(configuration: configuration) {
            Color.clear.frame(width: size.width, height: size.height)
        }
        #expect(controller.isVisible)
        #expect(frame == originalFrame)
        #expect(NSApp.keyWindow === keyWindow)
        #expect(NSApp.mainWindow === mainWindow)
    }
}
