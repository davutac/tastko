import AppKit
import CoreGraphics
import SwiftUI
import Testing

@testable import Tastko

// MARK: - FunctionToolbarTests
@MainActor
struct FunctionToolbarTests {
    // MARK: - Key Layers
    @Test func fnReplacesOnlyTheTwelveFunctionSlots() throws {
        let system = FunctionToolbarItem.items(functionIsActive: false)
        let function = FunctionToolbarItem.items(functionIsActive: true)
        #expect(system.count == 13)
        #expect(system.map(\.id) == function.map(\.id))
        #expect(function.first?.action == .key(.escape))
        #expect(
            function.dropFirst().map(\.action)
                == FunctionToolbarItem.functionKeys.map { .key($0) }
        )
        #expect(system[1].action == .system(.brightnessDown))
        #expect(system[8].action == .system(.playPause))
        #expect(system[12].action == .system(.volumeUp))
        let action = KeyAction.toggleFunctionToolbar
        #expect(
            try JSONDecoder().decode(KeyAction.self, from: JSONEncoder().encode(action)) == action
        )
        #expect(!action.isRepeatable)
    }

    // MARK: - System Events
    @Test(arguments: SystemControl.allCases.filter { $0.keyType != nil })
    func systemKeysUsePairedAuxiliaryEvents(_ control: SystemControl) throws {
        let down = try MacOSSystemControlPerformer.event(for: control, keyDown: true)
        let up = try MacOSSystemControlPerformer.event(for: control, keyDown: false)
        #expect(down.type == .systemDefined)
        #expect(up.type == .systemDefined)
        #expect(down.subtype.rawValue == 8)
        #expect(down.data1 >> 16 == control.keyType)
        #expect(up.data1 >> 16 == control.keyType)
        #expect((down.data1 >> 8) & 0xff == 10)
        #expect((up.data1 >> 8) & 0xff == 11)
        #expect(down.cgEvent != nil)
        #expect(up.cgEvent != nil)
    }

    // MARK: - Brightness Delivery
    @Test(arguments: [SystemControl.brightnessDown, .brightnessUp])
    func brightnessButtonsAdjustTheDisplayDirectly(_ control: SystemControl) async throws {
        var adjustments: [Float] = []
        let performer = MacOSSystemControlPerformer(adjustBrightness: { adjustments.append($0) })
        try await performer.perform(control)
        #expect(control.keyType == nil)
        #expect(adjustments == [control == .brightnessDown ? -0.0625 : 0.0625])
    }

    @Test func brightnessFailureIsPropagated() async {
        enum Failure: Error { case unavailable }
        let performer = MacOSSystemControlPerformer(adjustBrightness: { _ in
            throw Failure.unavailable
        })
        await #expect(throws: Failure.unavailable) {
            try await performer.perform(.brightnessUp)
        }
    }

    // MARK: - Geometry
    @Test(arguments: [CGSize(width: 708, height: 237), CGSize(width: 900, height: 400)])
    func toolbarResizingPreservesNormalKeyScaleAndWidth(_ panelSize: CGSize) {
        let origin = CGPoint(x: 80, y: 100)
        for width in [CGFloat(640), 820, 1_200] {
            let closed = configuration(panelSize, width: width, origin: origin, progress: 0)
            for progress in [CGFloat(0), 0.25, 0.5, 0.75, 1, 0.5, 0] {
                let current = configuration(
                    panelSize,
                    width: width,
                    origin: origin,
                    progress: progress
                )
                let rowHeight =
                    PanelEditorWindowMetrics.functionToolbarBaseHeight
                    * (width - 2 * KeyboardDesign.Metrics.panelInset) / panelSize.width
                    * progress
                #expect(abs(current.size.height - rowHeight - closed.size.height) < 0.001)
                #expect(current.size.width == closed.size.width)
                #expect(current.origin == closed.origin)
                #expect(current.minSize.width == closed.minSize.width)
                #expect(current.maxSize.width == closed.maxSize.width)
                #expect(current.storageKey == closed.storageKey)
                #expect(current.contentHeightForWidth?(width) == current.size.height)
            }
        }
    }

    @Test func growingNearTheTopMovesOnlyEnoughToStayOnScreen() {
        let screen = CGRect(x: -1_440, y: -200, width: 1_440, height: 900)
        let origin = CGPoint(x: -1_000, y: 400)
        let fitted = PanelEditorWindowMetrics.fittedOrigin(
            origin,
            size: CGSize(width: 820, height: 350),
            in: screen
        )
        #expect(fitted == CGPoint(x: -1_000, y: 350))
        #expect(
            PanelEditorWindowMetrics.fittedOrigin(
                origin,
                size: CGSize(width: 820, height: 250),
                in: screen
            ) == origin
        )
    }

    @Test func actualWindowResizingTracksToolbarProgressWithoutReplacingContent() throws {
        let controller = AlwaysOnTopWindowController()
        let initialWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        var reportedFrame = CGRect.zero
        let panelSize = CGSize(width: 708, height: 237)
        let origin = CGPoint(x: 100, y: 100)
        var initial = configuration(panelSize, width: 820, origin: origin, progress: 0)
        initial.sizeDidChange = { reportedFrame.size = $0 }
        initial.originDidChange = { reportedFrame.origin = $0 }
        controller.show(configuration: initial) { Color.clear }
        let panel = try #require(
            NSApp.windows.first { !initialWindows.contains(ObjectIdentifier($0)) }
                as? AlwaysOnTopPanel
        )
        defer {
            controller.hide()
            for window in NSApp.windows where !initialWindows.contains(ObjectIdentifier(window)) {
                window.close()
            }
        }
        for progress in [CGFloat(0.2), 0.5, 1, 0.5, 0, 1, 0] {
            var current = configuration(panelSize, width: 820, origin: origin, progress: progress)
            current.sizeDidChange = { reportedFrame.size = $0 }
            current.originDidChange = { reportedFrame.origin = $0 }
            controller.updateGeometry(configuration: current)
            #expect(abs(reportedFrame.height - current.size.height) <= 1)
            #expect(reportedFrame.width == 820)
            #expect(reportedFrame.origin == origin)
            #expect(controller.isVisible)
            let proposed = panel.windowWillResize(panel, to: CGSize(width: 900, height: 1_100))
            #expect(
                abs(proposed.height - (current.contentHeightForWidth?(proposed.width) ?? 0)) <= 1
            )
        }
    }

    // MARK: - Animated Window Geometry
    @Test(arguments: [CGSize(width: 708, height: 237), CGSize(width: 900, height: 400)])
    func manualResizeAlwaysFitsChromeToolbarAndKeyboard(_ panelSize: CGSize) {
        for progress in [CGFloat(0), 1] {
            let configuration = configuration(
                panelSize,
                width: 820,
                origin: CGPoint(x: 100, y: 100),
                progress: progress
            )
            let panel = AlwaysOnTopPanel(configuration: configuration)
            panel.contentView = NSView(frame: CGRect(origin: .zero, size: configuration.size))
            defer { panel.close() }
            for width in [CGFloat(640), 1_000, 720] {
                for proposedHeight in [CGFloat(100), 1_100] {
                    let constrained = panel.windowWillResize(
                        panel,
                        to: CGSize(width: width, height: proposedHeight)
                    )
                    panel.setFrame(
                        CGRect(origin: panel.frame.origin, size: constrained),
                        display: false
                    )
                    let actual = panel.contentSize(fallback: .zero)
                    #expect(actual.width == width)
                    #expect(
                        abs(actual.height - (configuration.contentHeightForWidth?(width) ?? 0)) <= 1
                    )
                }
            }
        }
    }

    @Test func repeatedAnimatedCyclesPreserveTheWindowAnchorAndPersistOnlyEndpoints() async throws {
        let controller = AlwaysOnTopWindowController()
        let panelSize = CGSize(width: 708, height: 237)
        let origin = CGPoint(x: 100, y: 100)
        var publications = 0
        var closed = configuration(panelSize, width: 820, origin: origin, progress: 0)
        closed.sizeDidChange = { _ in publications += 1 }
        var opened = configuration(panelSize, width: 820, origin: origin, progress: 1)
        opened.sizeDidChange = { _ in publications += 1 }
        controller.show(configuration: closed) { Color.clear }
        defer { controller.hide() }
        let initialFrame = try #require(controller.frame)
        let rowHeight = opened.size.height - closed.size.height

        for _ in 0..<3 {
            for target in [opened, closed] {
                let before = publications
                var completed = false
                var intermediateFrames: [CGRect] = []
                controller.animateGeometry(configuration: target, duration: 0.1) { fraction in
                    if fraction < 1 {
                        #expect(publications == before)
                        if let frame = controller.frame { intermediateFrames.append(frame) }
                    }
                    completed = fraction == 1
                }
                try await waitForAnimation { completed }
                #expect(completed)
                #expect(publications == before + 1)
                #expect(!intermediateFrames.isEmpty)
                for frame in intermediateFrames {
                    #expect(frame.origin == initialFrame.origin)
                    #expect(frame.width == initialFrame.width)
                    #expect(frame.height >= initialFrame.height)
                    #expect(frame.height <= initialFrame.height + rowHeight + 1)
                }
                let actual = try #require(controller.frame)
                #expect(actual.origin == initialFrame.origin)
                #expect(actual.width == initialFrame.width)
                #expect(abs(actual.height - target.size.height) <= 1)
            }
            #expect(controller.frame == initialFrame)
        }

        var reversed = false
        var completed = false
        let before = publications
        controller.animateGeometry(configuration: opened, duration: 0.2) { fraction in
            guard fraction > 0, !reversed else { return }
            reversed = true
            let frameAtReversal = controller.frame
            controller.animateGeometry(configuration: closed, duration: 0.1) { fraction in
                completed = fraction == 1
            }
            #expect(controller.frame == frameAtReversal)
        }
        try await waitForAnimation { completed }
        #expect(reversed && completed)
        #expect(publications == before + 1)
        #expect(controller.frame == initialFrame)
    }

    @Test func immediateGeometryAndHidingCancelPendingFrames() async throws {
        let controller = AlwaysOnTopWindowController()
        let size = CGSize(width: 708, height: 237)
        let closed = configuration(size, width: 820, origin: CGPoint(x: 100, y: 100), progress: 0)
        let opened = configuration(size, width: 820, origin: CGPoint(x: 100, y: 100), progress: 1)
        controller.show(configuration: closed) { Color.clear }
        defer { controller.hide() }
        var immediateValues: [CGFloat] = []
        controller.animateGeometry(configuration: opened, duration: 0) {
            immediateValues.append($0)
        }
        #expect(immediateValues == [1])
        #expect(abs((controller.frame?.height ?? 0) - opened.size.height) <= 1)
        var callbacks = 0
        controller.animateGeometry(configuration: closed, duration: 0.2) { _ in callbacks += 1 }
        controller.hide()
        let hiddenFrame = controller.frame
        try await Task.sleep(for: .milliseconds(250))
        #expect(callbacks == 0)
        #expect(controller.frame == hiddenFrame)
        #expect(!controller.isVisible)
    }

    // MARK: - Waiting
    /// Parallel main-actor tests can delay display-link frames by seconds, so the
    /// deadline only catches animations that stall, not slow ones.
    private func waitForAnimation(until isFinished: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !isFinished(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Configuration
    private func configuration(
        _ panelSize: CGSize,
        width: CGFloat,
        origin: CGPoint,
        progress: CGFloat
    ) -> AlwaysOnTopWindowConfiguration {
        PanelEditorWindowMetrics.expandedConfiguration(
            size: CGSize(width: width, height: 400),
            origin: origin,
            minimumScale: 0.5,
            panelSize: panelSize,
            functionToolbarProgress: progress
        )
    }
}
