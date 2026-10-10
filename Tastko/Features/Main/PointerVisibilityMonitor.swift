import AppKit
import Defaults

// MARK: - PointerVisibilityMonitor
/// Samples the pointer for hot corners and auto-hide. Samples run frequently only
/// while the pointer is active or dwelling in a corner; otherwise mouse events wake
/// sampling, and a single timer covers the inactivity deadline.
@MainActor
final class PointerVisibilityMonitor {
    private static let activeInterval: TimeInterval = 0.1
    private static let wakeEvents: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ]

    private var timer: Timer?
    private var isSamplingFrequently = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var settingsTask: Task<Void, Never>?
    private var policy = PointerVisibilityPolicy()
    private let cornerIndicator = HotCornerIndicatorController()
    private let perform: (PointerVisibilityAction) -> Void

    // MARK: - Initialization
    init(perform: @escaping (PointerVisibilityAction) -> Void) {
        self.perform = perform
    }

    // MARK: - Lifecycle
    func start() {
        guard globalMonitor == nil else { return }
        policy = PointerVisibilityPolicy()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.wakeEvents) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.wake() }
        }
        // Global monitors miss events sent to Tastko's own windows.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.wakeEvents) {
            [weak self] event in
            MainActor.assumeIsolated { self?.wake() }
            return event
        }
        // Settings can change from the keyboard alone, without a mouse event.
        settingsTask = Task { [weak self] in
            let keys: [Defaults._AnyKey] = [
                .pointerAutoHideEnabled, .pointerAutoHideDelay, .hotCornerDwellDuration,
            ]
            for await _ in Defaults.updates(keys, initial: false) {
                self?.resample()
            }
        }
        samplePointer()
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        settingsTask?.cancel()
        settingsTask = nil
        cancelTimer()
        cornerIndicator.update(nil)
    }

    // MARK: - Scheduling
    /// Starts frequent sampling. Events only start the timer, so pointer movement
    /// does not sample more often than the timer.
    private func wake() {
        guard globalMonitor != nil, !isSamplingFrequently else { return }
        samplePointer()
    }

    /// Samples now and reschedules, for changes that move the inactivity deadline.
    private func resample() {
        guard globalMonitor != nil else { return }
        cancelTimer()
        samplePointer()
    }

    private func scheduleNextSample(at time: TimeInterval) {
        if policy.needsFrequentSampling(at: time) {
            guard !isSamplingFrequently else { return }
            cancelTimer()
            isSamplingFrequently = true
            schedule(
                Timer(timeInterval: Self.activeInterval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.samplePointer() }
                }
            )
            return
        }
        cancelTimer()
        guard let deadline = policy.inactivityDeadline else { return }
        schedule(
            Timer(timeInterval: max(0, deadline - time), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.samplePointer() }
            }
        )
    }

    private func schedule(_ timer: Timer) {
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
        isSamplingFrequently = false
    }

    // MARK: - Sampling
    private func samplePointer() {
        let time = ProcessInfo.processInfo.systemUptime
        if let action = policy.update(
            location: NSEvent.mouseLocation,
            screenFrames: NSScreen.screens.map(\.frame),
            mouseButtonIsDown: NSEvent.pressedMouseButtons != 0,
            time: time,
            inactivityDelay: inactivityDelay,
            cornerDwell: Defaults[.hotCornerDwellDuration]
        ) {
            perform(action)
        }
        cornerIndicator.update(policy.cornerProgress)
        // `perform` can stop the monitor, for example when the screen locks.
        guard globalMonitor != nil else { return }
        scheduleNextSample(at: time)
    }

    // MARK: - Settings
    private var inactivityDelay: TimeInterval? {
        guard Defaults[.pointerAutoHideEnabled] else { return nil }
        let duration = Defaults[.pointerAutoHideDelay]
        guard duration.isFinite else { return PointerVisibilityPolicy.defaultInactivityDelay }
        return min(
            max(duration, PointerVisibilityPolicy.inactivityDelayRange.lowerBound),
            PointerVisibilityPolicy.inactivityDelayRange.upperBound
        )
    }
}
