import AppKit
import ApplicationServices
import Carbon

// MARK: - PredictionContextObservation
@MainActor
final class PredictionContextObservation {
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var element: AXUIElement?
    private var processIdentifier: pid_t?
    private var workspaceObserver: NSObjectProtocol?
    private var globalInputMonitor: Any?
    private var localInputMonitor: Any?
    private var inputSourceObserver: NSObjectProtocol?
    private let changed: () -> Void
    private let reset: () -> Void

    // MARK: - Initialization
    init(changed: @escaping () -> Void, reset: @escaping () -> Void) {
        self.changed = changed
        self.reset = reset
    }

    // MARK: - Lifecycle
    func start() {
        stop()
        observeExternalInput()
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reset()
                self?.observeApplication()
            }
        }
        observeApplication()
    }

    func stop() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
        if let globalInputMonitor { NSEvent.removeMonitor(globalInputMonitor) }
        if let localInputMonitor { NSEvent.removeMonitor(localInputMonitor) }
        globalInputMonitor = nil
        localInputMonitor = nil
        if let inputSourceObserver {
            DistributedNotificationCenter.default().removeObserver(inputSourceObserver)
        }
        inputSourceObserver = nil
        removeAXObserver()
    }

    // MARK: - Untracked Input
    private func observeExternalInput() {
        let events: NSEvent.EventTypeMask = [
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown,
        ]
        globalInputMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) {
            [weak self] event in
            MainActor.assumeIsolated { self?.externalInput(event) }
        }
        localInputMonitor = NSEvent.addLocalMonitorForEvents(matching: events) {
            [weak self] event in
            MainActor.assumeIsolated {
                // The floating keyboard must preserve the receiving app's session.
                if event.type == .keyDown || !(event.window is AlwaysOnTopPanel) {
                    self?.externalInput(event)
                }
            }
            return event
        }
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset() }
        }
    }

    func externalInput(_ event: NSEvent) {
        guard
            event.cgEvent?.getIntegerValueField(.eventSourceUserData)
                != CGKeyboardEventPoster.predictionEventTag
        else { return }
        reset()
    }

    // MARK: - Application Focus
    /// Observes the app that owns keyboard focus. That can differ from the frontmost
    /// app, for example in non-activating panels such as Spotlight.
    func observeApplication(
        _ pid: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier
    ) {
        guard pid != processIdentifier else { return }
        removeAXObserver()
        guard let pid, pid != ProcessInfo.processInfo.processIdentifier,
            AXIsProcessTrusted()
        else { return }

        var observer: AXObserver?
        let result = AXObserverCreate(
            pid,
            { _, _, notification, context in
                guard let context else { return }
                // This observer is installed exclusively on the main run loop.
                MainActor.assumeIsolated {
                    let observation = Unmanaged<PredictionContextObservation>
                        .fromOpaque(context).takeUnretainedValue()
                    if notification as String == kAXFocusedUIElementChangedNotification
                        || notification as String == kAXFocusedWindowChangedNotification
                    {
                        observation.reset()
                    }
                    else {
                        observation.changed()
                    }
                }
            },
            &observer
        )
        guard result == .success, let observer else { return }

        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.05)
        self.observer = observer
        self.application = application
        self.processIdentifier = pid
        for notification in [
            kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification,
        ] {
            AXObserverAddNotification(
                observer,
                application,
                notification as CFString,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    // MARK: - Text and Selection
    func observeElement(_ newElement: AXUIElement?) {
        if let element, let newElement, CFEqual(element, newElement) { return }
        guard let observer else { return }
        let notifications = [kAXValueChangedNotification, kAXSelectedTextChangedNotification]
        if let element {
            for notification in notifications {
                AXObserverRemoveNotification(observer, element, notification as CFString)
            }
        }
        element = newElement
        if let newElement {
            for notification in notifications {
                // Unsupported notifications are covered by the service's fallback refresh.
                AXObserverAddNotification(
                    observer,
                    newElement,
                    notification as CFString,
                    Unmanaged.passUnretained(self).toOpaque()
                )
            }
        }
    }

    private func removeAXObserver() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observer = nil
        application = nil
        element = nil
        processIdentifier = nil
    }
}
