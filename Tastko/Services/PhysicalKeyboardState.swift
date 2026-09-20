import AppKit
import ApplicationServices
import IOKit
import Observation

// MARK: - PhysicalKeyboardState
@Observable
@MainActor
final class PhysicalKeyboardState {
    static let shared = PhysicalKeyboardState()
    private(set) var snapshot = PhysicalKeyboardSnapshot()
    @ObservationIgnored private var localMonitor: Any?
    @ObservationIgnored private var globalMonitor: Any?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var reconciliationTimer: Timer?
    @ObservationIgnored private var controlDates: [SystemControl: Date] = [:]
    @ObservationIgnored private let readHardware: () -> PhysicalKeyboardSnapshot
    @ObservationIgnored private let canObserve: () -> Bool
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var syntheticKeys: Set<Key> = []
    @ObservationIgnored private var syntheticKeysDown: Set<Key> = []
    @ObservationIgnored private var overlappingPhysicalKeys: Set<Key> = []

    // MARK: - Initialization
    init(
        readHardware: @escaping () -> PhysicalKeyboardSnapshot = PhysicalKeyboardState
            .hardwareSnapshot,
        canObserve: @escaping () -> Bool = {
            AXIsProcessTrusted() || CGPreflightListenEventAccess()
        }
    ) {
        self.readHardware = readHardware
        self.canObserve = canObserve
    }

    // MARK: - Lifecycle
    func start() {
        guard !isRunning else {
            refresh()
            return
        }
        isRunning = true
        let events: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged, .systemDefined]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
            return event
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            workspaceObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in MainActor.assumeIsolated { self?.refresh() }
                }
            )
        }
        for name in [
            NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification,
        ] {
            workspaceObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in MainActor.assumeIsolated { self?.reset() }
                }
            )
        }
        // Recover missed releases and permission changes without retaining typed text.
        reconciliationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
            [weak self] _ in MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func stop() {
        isRunning = false
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        reconciliationTimer?.invalidate()
        reconciliationTimer = nil
        reset()
    }

    func reset() {
        snapshot = PhysicalKeyboardSnapshot()
        controlDates.removeAll()
        overlappingPhysicalKeys.removeAll()
    }

    func refresh() {
        guard canObserve() else {
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            globalMonitor = nil
            reset()
            return
        }
        if isRunning, globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.keyDown, .keyUp, .flagsChanged, .systemDefined]
            ) { [weak self] event in
                MainActor.assumeIsolated { self?.receive(event) }
            }
        }
        var current = filteringSyntheticKeys(from: readHardware())
        controlDates = controlDates.filter { Date().timeIntervalSince($0.value) < 2 }
        current.pressedControls = Set(controlDates.keys)
        if current != snapshot { snapshot = current }
    }

    // MARK: - Events
    func receive(_ event: NSEvent) {
        guard canObserve() else {
            reset()
            return
        }
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData)
            == CGKeyboardEventPoster.predictionEventTag
        {
            if event.type == .keyDown || event.type == .keyUp,
                let key = Key(rawValue: event.keyCode)
            {
                // Observed events can lag behind a newer posted press.
                maskSyntheticKey(key)
            }
            return
        }
        switch event.type {
        case .keyDown, .keyUp:
            guard let key = Key(rawValue: event.keyCode) else { return }
            recordPhysicalKey(key, isDown: event.type == .keyDown)
            snapshot.setKey(key, isDown: event.type == .keyDown)
        case .flagsChanged:
            let rawHardware = readHardware()
            if let key = Key(rawValue: event.keyCode) {
                recordPhysicalKey(key, isDown: rawHardware.pressedKeys.contains(key))
            }
            let hardware = filteringSyntheticKeys(from: rawHardware)
            snapshot.modifiers = hardware.modifiers
            snapshot.isCapsLockEnabled = hardware.isCapsLockEnabled
            for key in ModifierKey.allCases.map(\.key) + [.capsLock] {
                snapshot.setKey(key, isDown: hardware.pressedKeys.contains(key))
            }
        case .systemDefined:
            guard event.subtype.rawValue == Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                let control = Self.control(for: (event.data1 >> 16) & 0xFFFF)
            else { return }
            let state = (event.data1 >> 8) & 0xFF
            if state == NX_KEYDOWN {
                snapshot.pressedControls.insert(control)
                controlDates[control] = Date()
            }
            else if state == NX_KEYUP {
                snapshot.pressedControls.remove(control)
                controlDates.removeValue(forKey: control)
            }
        default:
            break
        }
    }

    // MARK: - Synthetic Input
    func recordPostedKey(_ key: Key, isDown: Bool) {
        maskSyntheticKey(key)
        if isDown {
            syntheticKeysDown.insert(key)
        }
        else {
            syntheticKeysDown.remove(key)
        }
    }

    // MARK: - Poll Masking
    private func maskSyntheticKey(_ key: Key) {
        if syntheticKeys.insert(key).inserted, snapshot.pressedKeys.contains(key) {
            overlappingPhysicalKeys.insert(key)
        }
    }

    // MARK: - Physical Overlap
    private func recordPhysicalKey(_ key: Key, isDown: Bool) {
        guard syntheticKeys.contains(key) else { return }
        if isDown {
            overlappingPhysicalKeys.insert(key)
        }
        else {
            overlappingPhysicalKeys.remove(key)
        }
    }

    // MARK: - Poll Reconciliation
    private func filteringSyntheticKeys(from hardware: PhysicalKeyboardSnapshot)
        -> PhysicalKeyboardSnapshot
    {
        // Posting is asynchronous: keep masking a released virtual key until the
        // system state catches up. Real key events still track overlapping presses.
        let released = syntheticKeys.subtracting(syntheticKeysDown)
            .subtracting(hardware.pressedKeys).subtracting(overlappingPhysicalKeys)
        syntheticKeys.subtract(released)
        let excluded = syntheticKeys.subtracting(overlappingPhysicalKeys)
        var current = hardware
        current.pressedKeys.subtract(excluded)
        current.pressedKeys.formUnion(overlappingPhysicalKeys)
        current.modifiers = Set(
            ModifierKey.allCases.filter { current.pressedKeys.contains($0.key) }
        )
        return current
    }

    // MARK: - Hardware
    nonisolated static func hardwareSnapshot() -> PhysicalKeyboardSnapshot {
        let keys = Set(
            Key.allCases.filter {
                CGEventSource.keyState(.hidSystemState, key: $0.cgKeyCode)
            }
        )
        // Caps Lock is a system latch, not a physical key-down flag. Read the same
        // IOHID state that SystemCapsLock.toggle verifies; HID event flags can disagree.
        let capsLockEnabled =
            SystemCapsLock.currentState()
            ?? CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        return hardwareSnapshot(
            pressedKeys: keys,
            flags: CGEventSource.flagsState(.hidSystemState),
            capsLockEnabled: capsLockEnabled
        )
    }

    // MARK: - Hardware State Reconciliation
    nonisolated static func hardwareSnapshot(
        pressedKeys: Set<Key>,
        flags: CGEventFlags,
        capsLockEnabled: Bool? = nil
    ) -> PhysicalKeyboardSnapshot {
        var keys = pressedKeys
        // Caps Lock's keycode bit can stay set after the key is released, even
        // while the lock is off. Its separate latch state drives the highlight.
        keys.remove(.capsLock)
        // Fn's keycode bit can remain set while Fn is up, or be absent while Fn is down.
        // Its modifier flag is authoritative in both cases.
        keys.remove(.function)
        if flags.contains(.maskSecondaryFn) { keys.insert(.function) }
        let modifiers = Set(ModifierKey.allCases.filter { keys.contains($0.key) })
        return PhysicalKeyboardSnapshot(
            pressedKeys: keys,
            modifiers: modifiers,
            isCapsLockEnabled: capsLockEnabled ?? flags.contains(.maskAlphaShift)
        )
    }

    // MARK: - Media Keys
    nonisolated static func control(for keyType: Int) -> SystemControl? {
        switch Int32(keyType) {
        case NX_KEYTYPE_BRIGHTNESS_DOWN: .brightnessDown
        case NX_KEYTYPE_BRIGHTNESS_UP: .brightnessUp
        case NX_KEYTYPE_SOUND_DOWN: .volumeDown
        case NX_KEYTYPE_SOUND_UP: .volumeUp
        case NX_KEYTYPE_MUTE: .mute
        case NX_KEYTYPE_PLAY: .playPause
        case NX_KEYTYPE_PREVIOUS, NX_KEYTYPE_REWIND: .previousTrack
        case NX_KEYTYPE_NEXT, NX_KEYTYPE_FAST: .nextTrack
        default: nil
        }
    }
}
