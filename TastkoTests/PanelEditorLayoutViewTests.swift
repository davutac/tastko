import AppKit
import Observation
import SwiftUI
import Testing

@testable import Tastko

// MARK: - Layout Input Lifecycle
@Suite(.serialized)
@MainActor
struct PanelEditorLayoutViewTests {
    // MARK: - Automatic Layout Changes
    @Test(arguments: [false, true])
    func changingLayoutEndsHeldKeysButPreservesToggledModifiers(removesLayout: Bool) throws {
        let poster = FakeKeyboardEventPoster()
        let service = KeyboardService(
            targetResolver: FakeKeyboardTargetResolver(),
            eventPoster: poster
        )
        let selection = LayoutSelection()
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(
            rootView: LayoutHost(selection: selection)
                .environment(\.keyboardService, service)
        )
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.close() }
        hostingView.layoutSubtreeIfNeeded()

        let key = try service.beginPress(KeyStroke(.a))
        try service.toggleLatch(.leftShift)
        try service.toggleFunction()
        let session = service.inputSession

        if removesLayout {
            selection.isVisible = false
        }
        else {
            selection.identifier = "browser"
        }
        hostingView.layoutSubtreeIfNeeded()

        #expect(service.inputSession != session)
        #expect(service.latchedModifiers == [.leftShift])
        #expect(service.heldModifiers == [.function])
        #expect(poster.events.last == .key(.a, [.function], false))
        let count = poster.events.count
        try service.repeatPress(key)
        try service.endPress(key)
        #expect(poster.events.count == count)

        service.releaseAll()
        #expect(service.effectiveModifiers.isEmpty)
    }

    // MARK: - Swipe Trail
    @Test func swipeTrailDrawsAcrossTheWholePanel() throws {
        let swipe = SwipeTypingController(
            enabled: { true },
            inputAllowed: { true },
            language: { ("com.apple.keylayout.US", "en") },
            letter: { $0 == .a ? "a" : $0 == .s ? "s" : nil },
            vocabulary: { SwipeTestVocabulary.named($0) }
        )
        let panel = PanelEditorPanel(
            id: "trail",
            rawIdentifier: "trail",
            profileDisplayName: "Test",
            name: "trail",
            displayOrder: 0,
            size: CGSize(width: 400, height: 40),
            isDefaultHomePanel: true,
            associatedApplicationBundleIdentifiers: [],
            buttons: [
                trailButton(.a, x: 0),
                trailButton(.s, x: 360),
            ]
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(
            rootView: PanelEditorLayoutView(panel: panel)
                .environment(\.swipeTypingController, swipe)
        )
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.close() }
        hostingView.layoutSubtreeIfNeeded()

        // A swipe from a to s runs through the empty middle of the panel, far from either key.
        // With only these two keys, their 360 pt spacing is the pitch a swipe must exceed.
        #expect(
            swipe.begin(
                buttonID: "a",
                action: .keyStroke(KeyStroke(.a)),
                at: CGPoint(x: 20, y: 20),
                time: 0
            )
        )
        #expect(swipe.move(buttonID: "a", to: CGPoint(x: 390, y: 20), time: 0.2))
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try #require(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / hostingView.bounds.width
        let middle = try #require(bitmap.colorAt(x: Int(200 * scale), y: Int(50 * scale)))
        #expect(middle.alphaComponent > 0.2)
        let farBelow = try #require(bitmap.colorAt(x: Int(200 * scale), y: Int(90 * scale)))
        #expect(farBelow.alphaComponent < 0.05)
    }

    private func trailButton(_ key: Key, x: CGFloat) -> PanelEditorButton {
        PanelEditorButton(
            id: key == .a ? "a" : "s",
            frame: CGRect(x: x, y: 0, width: 40, height: 40),
            title: "",
            secondaryTitle: nil,
            fontSize: 12,
            backgroundColor: nil,
            foregroundColor: nil,
            shape: .rectangle,
            primaryAction: .keyStroke(KeyStroke(key)),
            secondaryAction: .none,
            pressBehavior: .pressAndRelease
        )
    }
}

// MARK: - Layout Selection Fixture
@Observable
@MainActor
private final class LayoutSelection {
    var identifier = "home"
    var isVisible = true
}

// MARK: - Layout Host Fixture
private struct LayoutHost: View {
    let selection: LayoutSelection

    // MARK: - Body
    var body: some View {
        if selection.isVisible {
            PanelEditorLayoutView(
                panel: PanelEditorPanel(
                    id: selection.identifier,
                    rawIdentifier: selection.identifier,
                    profileDisplayName: "Test",
                    name: selection.identifier,
                    displayOrder: 0,
                    size: CGSize(width: 200, height: 100),
                    isDefaultHomePanel: selection.identifier == "home",
                    associatedApplicationBundleIdentifiers: [],
                    buttons: []
                )
            )
        }
    }
}
