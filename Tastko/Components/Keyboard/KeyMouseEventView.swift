import AppKit
import SwiftUI

// MARK: - KeyMouseButton
enum KeyMouseButton: Hashable {
    case left
    case right

    // MARK: - Action
    var actionTrigger: KeyActionTrigger {
        switch self {
        case .left:
            .leftClick
        case .right:
            .rightClick
        }
    }
}

// MARK: - KeyMouseHitRegion
enum KeyMouseHitRegion: Hashable {
    case rectangle
    case isoReturn

    // MARK: - Hit Testing
    func contains(_ point: CGPoint, in bounds: CGRect) -> Bool {
        guard bounds.contains(point) else {
            return false
        }

        switch self {
        case .rectangle:
            return true
        case .isoReturn:
            return PanelEditorKeyShape(buttonShape: .isoReturn).path(in: bounds).contains(point)
        }
    }
}

// MARK: - KeyMouseEventView
struct KeyMouseEventView: NSViewRepresentable {
    @Binding var pressedButton: KeyMouseButton?
    var hitRegion: KeyMouseHitRegion = .rectangle
    let mousePressed: (KeyMouseButton) -> Void
    let mouseReleasedInside: (KeyMouseButton) -> Void
    let mouseCancelled: () -> Void

    // MARK: - Coordinator
    func makeCoordinator() -> Coordinator {
        Coordinator(
            pressedButton: $pressedButton,
            mousePressed: mousePressed,
            mouseReleasedInside: mouseReleasedInside,
            mouseCancelled: mouseCancelled
        )
    }

    // MARK: - NSView
    func makeNSView(context: Context) -> KeyMouseEventNSView {
        let view = KeyMouseEventNSView()

        view.delegate = context.coordinator
        view.hitRegion = hitRegion

        return view
    }

    func updateNSView(_ nsView: KeyMouseEventNSView, context: Context) {
        context.coordinator.pressedButton = $pressedButton
        context.coordinator.mousePressed = mousePressed
        context.coordinator.mouseReleasedInside = mouseReleasedInside
        context.coordinator.mouseCancelled = mouseCancelled
        nsView.delegate = context.coordinator
        nsView.hitRegion = hitRegion
    }

    // MARK: - Coordinator
    @MainActor
    final class Coordinator: KeyMouseEventNSViewDelegate {
        var pressedButton: Binding<KeyMouseButton?>
        var mousePressed: (KeyMouseButton) -> Void
        var mouseReleasedInside: (KeyMouseButton) -> Void
        var mouseCancelled: () -> Void

        // MARK: - Initialization
        init(
            pressedButton: Binding<KeyMouseButton?>,
            mousePressed: @escaping (KeyMouseButton) -> Void,
            mouseReleasedInside: @escaping (KeyMouseButton) -> Void,
            mouseCancelled: @escaping () -> Void
        ) {
            self.pressedButton = pressedButton
            self.mousePressed = mousePressed
            self.mouseReleasedInside = mouseReleasedInside
            self.mouseCancelled = mouseCancelled
        }

        // MARK: - KeyMouseEventNSViewDelegate
        func keyMouseEventView(
            _ view: KeyMouseEventNSView,
            didPress button: KeyMouseButton
        ) {
            pressedButton.wrappedValue = button
            mousePressed(button)
        }

        func keyMouseEventView(
            _ view: KeyMouseEventNSView,
            didReleaseInside button: KeyMouseButton
        ) {
            pressedButton.wrappedValue = nil
            mouseReleasedInside(button)
        }

        func keyMouseEventViewDidCancel(_ view: KeyMouseEventNSView) {
            pressedButton.wrappedValue = nil
            mouseCancelled()
        }
    }
}

// MARK: - KeyMouseEventNSViewDelegate
@MainActor
protocol KeyMouseEventNSViewDelegate: AnyObject {
    func keyMouseEventView(_ view: KeyMouseEventNSView, didPress button: KeyMouseButton)
    func keyMouseEventView(_ view: KeyMouseEventNSView, didReleaseInside button: KeyMouseButton)
    func keyMouseEventViewDidCancel(_ view: KeyMouseEventNSView)
}

// MARK: - KeyMouseEventNSView
@MainActor
final class KeyMouseEventNSView: NSView, WindowMouseInteractiveRegion {
    weak var delegate: (any KeyMouseEventNSViewDelegate)?
    var hitRegion: KeyMouseHitRegion = .rectangle

    private var pressedButton: KeyMouseButton?

    override var isFlipped: Bool {
        true
    }

    // MARK: - Hit Testing
    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard hitRegion.contains(localPoint, in: bounds) else {
            return nil
        }

        return super.hitTest(point)
    }

    // MARK: - First Mouse
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    // MARK: - Mouse Events
    override func mouseDown(with event: NSEvent) {
        beginTracking(.left)
    }

    override func rightMouseDown(with event: NSEvent) {
        beginTracking(.right)
    }

    override func mouseDragged(with event: NSEvent) {
        updateDrag(.left, with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        updateDrag(.right, with: event)
    }

    override func mouseUp(with event: NSEvent) {
        endTracking(.left, with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        endTracking(.right, with: event)
    }

    override func mouseExited(with event: NSEvent) {
        cancelTracking()
    }

    // MARK: - Tracking
    private func beginTracking(_ button: KeyMouseButton) {
        pressedButton = button
        delegate?.keyMouseEventView(self, didPress: button)
    }

    private func endTracking(_ button: KeyMouseButton, with event: NSEvent) {
        guard pressedButton == button else {
            return
        }

        pressedButton = nil
        let location = convert(event.locationInWindow, from: nil)

        if hitRegion.contains(location, in: bounds) {
            delegate?.keyMouseEventView(self, didReleaseInside: button)
        }
        else {
            delegate?.keyMouseEventViewDidCancel(self)
        }
    }

    private func cancelTracking() {
        guard pressedButton != nil else {
            return
        }

        pressedButton = nil
        delegate?.keyMouseEventViewDidCancel(self)
    }

    private func updateDrag(_ button: KeyMouseButton, with event: NSEvent) {
        guard pressedButton == button else {
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        if !hitRegion.contains(location, in: bounds) {
            cancelTracking()
        }
    }
}
