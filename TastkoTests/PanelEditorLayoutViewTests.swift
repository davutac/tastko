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
