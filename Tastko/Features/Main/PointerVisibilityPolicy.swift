import CoreGraphics
import Foundation

// MARK: - PointerVisibilityAction
nonisolated enum PointerVisibilityAction: Equatable {
    case toggle
    case hideForInactivity
    case restoreFromInactivity
}

// MARK: - HotCornerProgress
nonisolated struct HotCornerProgress {
    let screenFrame: CGRect
    let elapsed: TimeInterval
    let duration: TimeInterval

    var fraction: Double { min(1, max(0, elapsed / duration)) }
    var remaining: TimeInterval { max(0, duration - elapsed) }
}

// MARK: - PointerVisibilityPolicy
nonisolated struct PointerVisibilityPolicy {
    static let cornerSize: CGFloat = 6
    static let defaultCornerDwell: TimeInterval = 1.5
    static let cornerDwellRange: ClosedRange<Double> = 0.5...5
    static let defaultInactivityDelay: TimeInterval = 15
    static let inactivityDelayRange: ClosedRange<Double> = 5...120

    private var lastLocation: CGPoint?
    private var lastActivity: TimeInterval = 0
    private var currentCorner: CGRect?
    private var cornerEnteredAt: TimeInterval?
    private var didTriggerCorner = false
    private var didTriggerInactivity = false
    private var inactivityDelay: TimeInterval?
    private var cornerDwell = Self.defaultCornerDwell
    private(set) var cornerProgress: HotCornerProgress?

    /// How long after the last activity the pointer keeps being sampled frequently.
    static let activeSamplingWindow: TimeInterval = 0.5

    // MARK: - Sampling Schedule
    /// Whether the pointer needs frequent samples: it has not been sampled yet, moved
    /// recently, or is dwelling in a corner that has not triggered.
    func needsFrequentSampling(at time: TimeInterval) -> Bool {
        lastLocation == nil
            || time - lastActivity < Self.activeSamplingWindow
            || (currentCorner != nil && !didTriggerCorner)
    }

    /// When the pointer becomes inactive, if auto-hide has not already triggered.
    var inactivityDeadline: TimeInterval? {
        guard let inactivityDelay, !didTriggerInactivity else { return nil }
        return lastActivity + inactivityDelay
    }

    // MARK: - Pointer Updates
    mutating func update(
        location: CGPoint,
        screenFrames: [CGRect],
        mouseButtonIsDown: Bool,
        time: TimeInterval,
        inactivityDelay: TimeInterval? = Self.defaultInactivityDelay,
        cornerDwell: TimeInterval = Self.defaultCornerDwell
    ) -> PointerVisibilityAction? {
        cornerProgress = nil
        let cornerDwell = min(
            max(
                cornerDwell.isFinite ? cornerDwell : Self.defaultCornerDwell,
                Self.cornerDwellRange.lowerBound
            ),
            Self.cornerDwellRange.upperBound
        )
        if self.cornerDwell != cornerDwell {
            self.cornerDwell = cornerDwell
            cornerEnteredAt = nil
        }
        let settingsChanged = self.inactivityDelay != inactivityDelay
        self.inactivityDelay = inactivityDelay
        if settingsChanged {
            lastActivity = time
            didTriggerInactivity = false
        }

        let corner = screenFrames.first { frame in
            CGRect(
                x: frame.maxX - Self.cornerSize,
                y: frame.minY,
                width: Self.cornerSize,
                height: Self.cornerSize
            ).contains(location)
        }

        guard let previousLocation = lastLocation else {
            lastLocation = location
            lastActivity = time
            currentCorner = corner
            // Starting the app with the pointer in a corner is not a new entry.
            didTriggerCorner = corner != nil
            return nil
        }

        let moved = location != previousLocation
        lastLocation = location
        if moved || mouseButtonIsDown {
            lastActivity = time
            didTriggerInactivity = false
        }

        if corner != currentCorner {
            currentCorner = corner
            cornerEnteredAt = corner == nil ? nil : time
            didTriggerCorner = false
        }

        let shouldRestore = moved || (settingsChanged && inactivityDelay == nil)
        let movementAction: PointerVisibilityAction? = shouldRestore ? .restoreFromInactivity : nil
        guard !mouseButtonIsDown else {
            cornerEnteredAt = nil
            return movementAction
        }

        if let corner {
            if !didTriggerCorner {
                let enteredAt = cornerEnteredAt ?? time
                cornerEnteredAt = enteredAt
                if time - enteredAt >= cornerDwell {
                    didTriggerCorner = true
                    lastActivity = time
                    return .toggle
                }
                cornerProgress = HotCornerProgress(
                    screenFrame: corner,
                    elapsed: time - enteredAt,
                    duration: cornerDwell
                )
            }
            return movementAction
        }

        if let inactivityDelay, !didTriggerInactivity, time - lastActivity >= inactivityDelay {
            didTriggerInactivity = true
            return .hideForInactivity
        }
        return movementAction
    }
}
