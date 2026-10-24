import AppKit
import Testing

@testable import Tastko

// MARK: - PanelEditorWindowMetricsTests
@MainActor
struct PanelEditorWindowMetricsTests {
    // MARK: - Shared Geometry
    @Test func missingPanelUsesTheDefaultWindowProportions() {
        let configuration = PanelEditorWindowMetrics.expandedConfiguration(
            size: FloatingWindowDefaults.defaultSize,
            origin: nil,
            minimumScale: 0.5,
            panelSize: nil
        )

        #expect(configuration.size == FloatingWindowDefaults.defaultSize)
        #expect(
            configuration.contentHeightForWidth?(FloatingWindowDefaults.defaultSize.width)
                == FloatingWindowDefaults.defaultSize.height
        )
    }

    @Test func expandedWindowKeepsWidthAndOriginButRepairsAnUnfittedHeight() {
        let size = CGSize(width: 820, height: 1_100)
        let origin = CGPoint(x: 150, y: 90)
        let keyboardSize = CGSize(width: 708, height: 237)
        let configuration = PanelEditorWindowMetrics.expandedConfiguration(
            size: size,
            origin: origin,
            minimumScale: 0.5,
            panelSize: keyboardSize
        )

        #expect(configuration.size.width == size.width)
        #expect(
            configuration.size.height
                == PanelEditorWindowMetrics.contentHeight(for: keyboardSize, width: size.width)
        )
        #expect(configuration.origin == origin)
        #expect(!configuration.maintainsContentAspectRatio)
        #expect(
            configuration.contentHeightForWidth?(keyboardSize.width + 10)
                == keyboardSize.height + 10 + PanelEditorWindowMetrics.fixedChromeHeight
        )
        #expect(configuration.storageKey == "mainPanelEditorShared")
    }

    @Test func equalProportionProfilesKeepTheSameWindowGeometry() {
        let size = CGSize(width: 820, height: 430)
        let origin = CGPoint(x: 150, y: 90)
        let first = PanelEditorWindowMetrics.expandedConfiguration(
            size: size,
            origin: origin,
            minimumScale: 0.5,
            panelSize: CGSize(width: 708, height: 237)
        )
        let second = PanelEditorWindowMetrics.expandedConfiguration(
            size: first.size,
            origin: first.origin,
            minimumScale: 0.5,
            panelSize: CGSize(width: 1_416, height: 474)
        )

        #expect(first.size == second.size)
        #expect(first.origin == second.origin)
        #expect(first.storageKey == second.storageKey)
    }

    @Test func minimumScaleKeepsChromeAtItsFixedHeight() {
        let configuration = PanelEditorWindowMetrics.expandedConfiguration(
            size: CGSize(width: 1, height: 1),
            origin: nil,
            minimumScale: 0.5,
            panelSize: CGSize(width: 708, height: 237)
        )
        let chromeHeight = PanelEditorWindowMetrics.fixedChromeHeight

        #expect(configuration.size.width == 364)
        #expect(configuration.size.height == chromeHeight + 128.5)
        #expect(configuration.size == configuration.minSize)
    }

    // MARK: - Fixed Insets
    @Test(arguments: [CGFloat(0.5), 1, 2])
    func paddingLeavesEqualSpaceAroundUniformlyScaledKeys(_ scale: CGFloat) {
        let panelSize = CGSize(width: 708, height: 237)
        for progress in [CGFloat(0), 0.5, 1] {
            let size = PanelEditorWindowMetrics.contentSize(
                for: panelSize,
                scale: scale,
                functionToolbarProgress: progress
            )
            let toolbarHeight =
                PanelEditorWindowMetrics.functionToolbarBaseHeight * scale * progress
            let layoutWidth = size.width - 2 * KeyboardDesign.Metrics.panelInset
            let layoutHeight =
                size.height - PanelEditorWindowMetrics.fixedChromeHeight
                - toolbarHeight - 2 * KeyboardDesign.Metrics.panelInset
            #expect(layoutWidth == panelSize.width * scale)
            #expect(layoutHeight == panelSize.height * scale)
            #expect(
                PanelEditorWindowMetrics.keyboardScale(for: panelSize, width: size.width) == scale
            )
        }
    }

    @Test func reapplyingWindowConfigurationPreservesFrameAndPreventsTallEmptyWindows() {
        let keyboardSize = CGSize(width: 708, height: 237)
        let configuration = PanelEditorWindowMetrics.expandedConfiguration(
            size: CGSize(width: 820, height: 430),
            origin: CGPoint(x: 150, y: 90),
            minimumScale: 0.5,
            panelSize: keyboardSize
        )
        let panel = AlwaysOnTopPanel(configuration: configuration)
        defer { panel.close() }
        let originalFrame = panel.frame

        panel.apply(configuration)
        panel.applyContentSizeConstraints(
            configuration: configuration,
            contentMinimumSize: CGSize(width: 1_200, height: 700)
        )

        #expect(panel.frame == originalFrame)
        let proposedSize = CGSize(width: originalFrame.width, height: 1_100)
        let resizedFrame = panel.windowWillResize(panel, to: proposedSize)
        panel.setFrame(CGRect(origin: panel.frame.origin, size: resizedFrame), display: false)
        let resizedContent = panel.contentSize(fallback: .zero)
        #expect(resizedFrame.width == originalFrame.width)
        #expect(
            abs(
                resizedContent.height
                    - PanelEditorWindowMetrics.contentHeight(
                        for: keyboardSize,
                        width: resizedContent.width
                    )
            ) <= 1
        )
    }

    // MARK: - Titlebar Zoom
    @Test func titlebarDoubleClickCannotZoomTheResizableWindow() throws {
        let configuration = PanelEditorWindowMetrics.expandedConfiguration(
            size: CGSize(width: 820, height: 430),
            origin: CGPoint(x: 150, y: 90),
            minimumScale: 0.5,
            panelSize: CGSize(width: 708, height: 237)
        )
        let panel = AlwaysOnTopPanel(configuration: configuration)
        defer { panel.close() }
        let delegate = try #require(panel.delegate)

        #expect(panel.styleMask.contains(.resizable))
        #expect(
            delegate.windowShouldZoom?(panel, toFrame: panel.frame.insetBy(dx: -200, dy: -200))
                == false
        )
    }
}
