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
nonisolated enum KeyMouseHitRegion: Hashable {
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

// MARK: - KeyPointerDisposition
/// How a press goes on after the pointer moved.
enum KeyPointerDisposition: Equatable {
    /// As any key: leaving the key cancels the press.
    case standard
    /// The press follows the pointer outside the key until it is released.
    case tracking
    /// As `tracking`, and the key no longer shows as pressed (a swipe took over).
    case swiping
}

// MARK: - KeyPointerTracking
/// Where the pointer is during a press, for presses that may become swipes. Positions are in
/// the key view's coordinates, top-left origin; times are the events' timestamps.
struct KeyPointerTracking {
    /// The press went down here. Called before `mousePressed`.
    let began: (CGPoint, TimeInterval) -> Void
    /// The pointer moved while pressed.
    let moved: (CGPoint, TimeInterval) -> KeyPointerDisposition
    /// A press `moved` kept past the key was released: where, when, and whether inside the key.
    /// Called in place of `mouseReleasedInside` or `mouseCancelled`.
    let ended: (CGPoint, TimeInterval, Bool) -> Void
}

// MARK: - KeyMouseEventView
struct KeyMouseEventView: NSViewRepresentable {
    @Binding var pressedButton: KeyMouseButton?
    var hitRegion: KeyMouseHitRegion = .rectangle
    let mousePressed: (KeyMouseButton) -> Void
    let mouseReleasedInside: (KeyMouseButton) -> Void
    let mouseCancelled: () -> Void
    var pointer: KeyPointerTracking?

    // MARK: - Coordinator
    func makeCoordinator() -> Coordinator {
        Coordinator(
            pressedButton: $pressedButton,
            mousePressed: mousePressed,
            mouseReleasedInside: mouseReleasedInside,
            mouseCancelled: mouseCancelled,
            pointer: pointer
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
        context.coordinator.pointer = pointer
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
        var pointer: KeyPointerTracking?

        // MARK: - Initialization
        init(
            pressedButton: Binding<KeyMouseButton?>,
            mousePressed: @escaping (KeyMouseButton) -> Void,
            mouseReleasedInside: @escaping (KeyMouseButton) -> Void,
            mouseCancelled: @escaping () -> Void,
            pointer: KeyPointerTracking? = nil
        ) {
            self.pressedButton = pressedButton
            self.mousePressed = mousePressed
            self.mouseReleasedInside = mouseReleasedInside
            self.mouseCancelled = mouseCancelled
            self.pointer = pointer
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

        // MARK: - Pointer Tracking
        func keyMouseEventView(
            _ view: KeyMouseEventNSView,
            didBegin button: KeyMouseButton,
            at point: CGPoint,
            time: TimeInterval
        ) {
            pointer?.began(point, time)
        }

        func keyMouseEventView(
            _ view: KeyMouseEventNSView,
            didDrag button: KeyMouseButton,
            to point: CGPoint,
            time: TimeInterval
        ) -> KeyPointerDisposition {
            let disposition = pointer?.moved(point, time) ?? .standard
            if disposition == .swiping, pressedButton.wrappedValue != nil {
                pressedButton.wrappedValue = nil
            }
            return disposition
        }

        func keyMouseEventView(
            _ view: KeyMouseEventNSView,
            didEnd button: KeyMouseButton,
            at point: CGPoint,
            time: TimeInterval,
            inside: Bool
        ) {
            pressedButton.wrappedValue = nil
            pointer?.ended(point, time, inside)
        }
    }
}

// MARK: - KeyMouseEventNSViewDelegate
@MainActor
protocol KeyMouseEventNSViewDelegate: AnyObject {
    func keyMouseEventView(_ view: KeyMouseEventNSView, didPress button: KeyMouseButton)
    func keyMouseEventView(_ view: KeyMouseEventNSView, didReleaseInside button: KeyMouseButton)
    func keyMouseEventViewDidCancel(_ view: KeyMouseEventNSView)
    /// The press went down at `point`, before `didPress`.
    func keyMouseEventView(
        _ view: KeyMouseEventNSView,
        didBegin button: KeyMouseButton,
        at point: CGPoint,
        time: TimeInterval
    )
    /// The pointer moved during the press; the answer says whether leaving the key cancels it.
    func keyMouseEventView(
        _ view: KeyMouseEventNSView,
        didDrag button: KeyMouseButton,
        to point: CGPoint,
        time: TimeInterval
    ) -> KeyPointerDisposition
    /// A press kept past its key was released. Sent in place of `didReleaseInside` and
    /// `keyMouseEventViewDidCancel`.
    func keyMouseEventView(
        _ view: KeyMouseEventNSView,
        didEnd button: KeyMouseButton,
        at point: CGPoint,
        time: TimeInterval,
        inside: Bool
    )
}

// MARK: - KeyMouseEventNSViewDelegate Defaults
extension KeyMouseEventNSViewDelegate {
    func keyMouseEventView(
        _ view: KeyMouseEventNSView,
        didBegin button: KeyMouseButton,
        at point: CGPoint,
        time: TimeInterval
    ) {}

    func keyMouseEventView(
        _ view: KeyMouseEventNSView,
        didDrag button: KeyMouseButton,
        to point: CGPoint,
        time: TimeInterval
    ) -> KeyPointerDisposition {
        .standard
    }

    func keyMouseEventView(
        _ view: KeyMouseEventNSView,
        didEnd button: KeyMouseButton,
        at point: CGPoint,
        time: TimeInterval,
        inside: Bool
    ) {
        if inside {
            keyMouseEventView(view, didReleaseInside: button)
        }
        else {
            keyMouseEventViewDidCancel(view)
        }
    }
}

// MARK: - KeyMouseEventNSView
@MainActor
final class KeyMouseEventNSView: NSView, WindowMouseInteractiveRegion {
    weak var delegate: (any KeyMouseEventNSViewDelegate)?
    var hitRegion: KeyMouseHitRegion = .rectangle

    private var pressedButton: KeyMouseButton?
    /// Whether the press follows the pointer outside the key, as a swipe does.
    private var tracksOutside = false

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
        beginTracking(.left, with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        beginTracking(.right, with: event)
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
        guard !tracksOutside else { return }
        cancelTracking()
    }

    // MARK: - Tracking
    private func beginTracking(_ button: KeyMouseButton, with event: NSEvent) {
        pressedButton = button
        tracksOutside = false
        delegate?.keyMouseEventView(
            self,
            didBegin: button,
            at: convert(event.locationInWindow, from: nil),
            time: event.timestamp
        )
        delegate?.keyMouseEventView(self, didPress: button)
    }

    private func endTracking(_ button: KeyMouseButton, with event: NSEvent) {
        guard pressedButton == button else {
            return
        }

        pressedButton = nil
        let location = convert(event.locationInWindow, from: nil)

        if tracksOutside {
            tracksOutside = false
            delegate?.keyMouseEventView(
                self,
                didEnd: button,
                at: location,
                time: event.timestamp,
                inside: hitRegion.contains(location, in: bounds)
            )
        }
        else if hitRegion.contains(location, in: bounds) {
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
        tracksOutside = false
        delegate?.keyMouseEventViewDidCancel(self)
    }

    private func updateDrag(_ button: KeyMouseButton, with event: NSEvent) {
        guard pressedButton == button else {
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        let disposition =
            delegate?.keyMouseEventView(
                self,
                didDrag: button,
                to: location,
                time: event.timestamp
            ) ?? .standard
        if disposition != .standard { tracksOutside = true }
        if !tracksOutside, !hitRegion.contains(location, in: bounds) {
            cancelTracking()
        }
    }
}
