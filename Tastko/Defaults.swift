import CoreGraphics
import Defaults

// MARK: - StoredWindowSize
struct StoredWindowSize: Codable, Defaults.Serializable, Equatable {
    var width: CGFloat
    var height: CGFloat

    init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }

    init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }

    var cgSize: CGSize {
        CGSize(width: width, height: height)
    }
}

// MARK: - StoredWindowOrigin
struct StoredWindowOrigin: Codable, Defaults.Serializable, Equatable {
    var x: CGFloat
    var y: CGFloat

    init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    init(_ origin: CGPoint) {
        self.init(x: origin.x, y: origin.y)
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

// MARK: - FloatingWindowDefaults
enum FloatingWindowDefaults {
    nonisolated static let defaultSize = CGSize(width: 640, height: 300)
    nonisolated static let defaultMinimumSize = CGSize(width: 640, height: 240)
    nonisolated static let defaultMaximumSize = CGSize(width: 2_400, height: 1_200)
    nonisolated static let defaultMiniSize = CGSize(width: 96, height: 96)
    nonisolated static let miniButtonSideLength: CGFloat = 52
    nonisolated static let miniContentPadding: CGFloat = 8
    nonisolated static let defaultMinimumKeyboardScale: CGFloat = 0.5
    nonisolated static let allowedMinimumKeyboardScaleRange: ClosedRange<CGFloat> = 0.25...1
    nonisolated static let allowedMiniSideLengthRange: ClosedRange<CGFloat> =
        minimumMiniSideLength...160
    nonisolated static let maximumStoredOriginMagnitude: CGFloat = 100_000

    nonisolated static var minimumMiniSideLength: CGFloat {
        miniButtonSideLength + (miniContentPadding * 2)
    }

    nonisolated static var minimumMiniSize: CGSize {
        CGSize(
            width: minimumMiniSideLength,
            height: minimumMiniSideLength
        )
    }

    nonisolated static var maximumMiniSize: CGSize {
        CGSize(
            width: allowedMiniSideLengthRange.upperBound,
            height: allowedMiniSideLengthRange.upperBound
        )
    }

    static var size: CGSize {
        Defaults[.floatingWindowSize].cgSize.validWindowConstraint(fallback: defaultSize)
    }

    static var miniSize: CGSize {
        sanitizedMiniSize(Defaults[.floatingWindowMiniSize].cgSize)
    }

    static var minimumKeyboardScale: CGFloat {
        CGFloat(Defaults[.floatingWindowMinimumScale])
            .clamped(to: allowedMinimumKeyboardScaleRange)
    }

    static var origin: CGPoint? {
        sanitizedOrigin(Defaults[.floatingWindowOrigin]?.cgPoint)
    }

    static var miniOrigin: CGPoint? {
        sanitizedOrigin(Defaults[.floatingWindowMiniOrigin]?.cgPoint)
    }

    // MARK: - Sanitize
    static func sanitizedMiniSize(_ size: CGSize) -> CGSize {
        let side = miniSideLength(for: size).sanitized(
            default: defaultMiniSize.width,
            in: allowedMiniSideLengthRange
        )

        return CGSize(width: side, height: side)
    }

    static func sanitizedOrigin(_ origin: CGPoint?) -> CGPoint? {
        guard
            let origin,
            origin.x.isFinite,
            origin.y.isFinite,
            abs(origin.x) <= maximumStoredOriginMagnitude,
            abs(origin.y) <= maximumStoredOriginMagnitude
        else { return nil }

        return origin
    }

    private static func miniSideLength(for size: CGSize) -> CGFloat {
        let validLengths = [size.width, size.height].filter { $0.isFinite && $0 > 0 }

        return validLengths.max() ?? defaultMiniSize.width
    }
}

// MARK: - Defaults.Keys Extension
extension Defaults.Keys {
    static let buttonSound = Defaults.Key<ButtonSound>("buttonSound", default: .keyClick)
    static let customButtonSound = Defaults.Key<StoredButtonSound?>("customButtonSound")

    static let experimentalLockScreenDisplay = Defaults.Key<Bool>(
        "experimentalLockScreenDisplay",
        default: false
    )
    static let keyboardTheme = Defaults.Key<String>(
        "keyboardTheme",
        default: KeyboardTheme.defaultID
    )
    static let keyboardAppearance = Defaults.Key<KeyboardAppearance>(
        "keyboardAppearance",
        default: .system
    )
    static let keycapStyle = Defaults.Key<KeycapStyle>("keycapStyle", default: .mechanical)
    static let keycapCorners = Defaults.Key<KeycapCorners>("keycapCorners", default: .standard)

    static let functionToolbarVisible = Defaults.Key<Bool>("functionToolbarVisible", default: false)
    static let hotCornerDwellDuration = Defaults.Key<Double>(
        "hotCornerDwellDuration",
        default: PointerVisibilityPolicy.defaultCornerDwell
    )

    static let pointerAutoHideEnabled = Defaults.Key<Bool>("pointerAutoHideEnabled", default: true)
    static let pointerAutoHideDelay = Defaults.Key<Double>(
        "pointerAutoHideDelay",
        default: PointerVisibilityPolicy.defaultInactivityDelay
    )

    static let sentenceCompletionSystemPrompt = Defaults.Key<String>(
        "sentenceCompletionSystemPrompt",
        default: ""
    )
    static let textPredictionEnabled = Defaults.Key<Bool>("textPredictionEnabled", default: true)

    static let floatingWindowSize = Defaults.Key<StoredWindowSize>(
        "floatingWindowSize",
        default: StoredWindowSize(FloatingWindowDefaults.defaultSize)
    )

    static let floatingWindowMinimumScale = Defaults.Key<Double>(
        "floatingWindowMinimumScale",
        default: Double(FloatingWindowDefaults.defaultMinimumKeyboardScale)
    )

    static let floatingWindowMiniSize = Defaults.Key<StoredWindowSize>(
        "floatingWindowMiniSize",
        default: StoredWindowSize(FloatingWindowDefaults.defaultMiniSize)
    )

    static let floatingWindowOrigin = Defaults.Key<StoredWindowOrigin?>(
        "floatingWindowOrigin"
    )

    static let floatingWindowMiniOrigin = Defaults.Key<StoredWindowOrigin?>(
        "floatingWindowMiniOrigin"
    )

    static let selectedPanelEditorPanelID = Defaults.Key<String?>(
        "selectedPanelEditorPanelID"
    )
}

extension CGSize {
    // MARK: - Constraint
    func constrained(toAtLeast minimumSize: CGSize) -> CGSize {
        CGSize(
            width: max(width, minimumSize.width),
            height: max(height, minimumSize.height)
        )
    }
}

extension CGFloat {
    // MARK: - Sanitize
    fileprivate func sanitized(default defaultValue: CGFloat, in range: ClosedRange<CGFloat>)
        -> CGFloat
    {
        guard isFinite else { return defaultValue }

        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }

    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
