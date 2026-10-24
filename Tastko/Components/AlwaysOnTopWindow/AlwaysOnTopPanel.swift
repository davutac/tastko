import AppKit

// MARK: - AlwaysOnTopPanel
final class AlwaysOnTopPanel: NSPanel, NSWindowDelegate {
    var preventsHiding = false {
        didSet { canHide = !preventsHiding }
    }
    var sizeDidChange: ((CGSize) -> Void)?
    var originDidChange: ((CGPoint) -> Void)?
    var liveResizeDidChange: ((Bool) -> Void)?
    var contentSizeDidChangeDuringLiveResize: ((CGSize) -> Void)?

    private static let unrestrictedResizeIncrements = CGSize(width: 1, height: 1)
    private var contentHeightForWidth: (@MainActor (CGFloat) -> CGFloat)?

    // MARK: - Initialization
    init(configuration: AlwaysOnTopWindowConfiguration) {
        let initialFrame = NSRect(
            origin: Self.validOrigin(configuration.origin),
            size: configuration.size.validWindowConstraint(
                fallback: FloatingWindowDefaults.defaultSize
            )
        )

        super.init(
            contentRect: initialFrame,
            styleMask: Self.styleMask(for: configuration),
            backing: .buffered,
            defer: false
        )

        apply(configuration)
        backgroundColor = .clear
        isOpaque = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        delegate = self
    }

    override var canBecomeKey: Bool { false }

    override var canBecomeMain: Bool { false }

    // MARK: - Locked Visibility
    override func orderOut(_ sender: Any?) {
        guard !preventsHiding else { return }
        super.orderOut(sender)
    }

    override func miniaturize(_ sender: Any?) {
        guard !preventsHiding else { return }
        super.miniaturize(sender)
    }

    override func close() {
        guard !preventsHiding else { return }
        super.close()
    }

    // MARK: - Full-size Content Geometry
    func setFittedContentSize(_ size: NSSize) {
        guard styleMask.contains(.fullSizeContentView) else {
            super.setContentSize(size)
            return
        }
        let resizedFrame = CGRect(
            x: frame.minX,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        setFrame(resizedFrame, display: false)
    }

    // MARK: - Events
    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        applyDefaultCursorIfNeeded(for: event)
    }

    // MARK: - Configuration
    func apply(_ configuration: AlwaysOnTopWindowConfiguration) {
        contentHeightForWidth = configuration.contentHeightForWidth
        level = configuration.level
        collectionBehavior = configuration.collectionBehavior
        hidesOnDeactivate = configuration.hidesOnDeactivate
        isMovableByWindowBackground = configuration.isMovableByWindowBackground
        contentMinSize = configuration.minSize.validWindowConstraint(
            fallback: FloatingWindowDefaults.defaultMinimumSize
        )
        contentMaxSize = configuration.maxSize.validWindowConstraint(
            fallback: FloatingWindowDefaults.defaultMaximumSize
        )
        hasShadow = configuration.hasShadow

        applyResizableBehavior(configuration)
        applyInitialPlacement(configuration)
    }

    func applyContentSizeConstraints(
        configuration: AlwaysOnTopWindowConfiguration,
        contentMinimumSize: CGSize
    ) {
        let resolvedContentSize = contentMinimumSize.validWindowConstraint(
            fallback: configuration.size
        )
        .clamped(
            minimumSize: configuration.minSize,
            maximumSize: configuration.maxSize
        )
        let minimumContentSize =
            configuration.allowsResizing
            ? configuration.minSize.validWindowConstraint(
                fallback: resolvedContentSize
            )
            : resolvedContentSize
        contentMinSize = minimumContentSize

        guard configuration.allowsResizing else {
            contentMaxSize = minimumContentSize
            applyUnrestrictedResizeBehavior()
            setFittedContentSize(
                minimumContentSize.validWindowConstraint(fallback: configuration.size)
            )
            return
        }

        let stableMinimumSize = configuration.minSize.validWindowConstraint(
            fallback: minimumContentSize.validWindowConstraint(
                fallback: FloatingWindowDefaults.defaultMinimumSize
            )
        )
        contentMinSize = stableMinimumSize

        let currentContentSize = contentSize(fallback: configuration.size)
        let constrainedContentSize = currentContentSize.constrained(
            toAtLeast: stableMinimumSize
        )

        if constrainedContentSize != currentContentSize {
            setFittedContentSize(constrainedContentSize)
        }

        guard configuration.maintainsContentAspectRatio else {
            contentAspectRatio = .zero
            applyUnrestrictedResizeBehavior()
            return
        }

        contentAspectRatio =
            configuration.contentAspectRatio?
            .validWindowConstraint(fallback: stableMinimumSize)
            ?? stableMinimumSize
    }

    func contentSize(fallback: CGSize) -> CGSize {
        if styleMask.contains(.fullSizeContentView) {
            return frame.size
        }
        if let contentSize = contentView?.bounds.size, contentSize.isValidWindowConstraint {
            return contentSize
        }

        if contentLayoutRect.size.isValidWindowConstraint {
            return contentLayoutRect.size
        }

        return fallback.validWindowConstraint(fallback: FloatingWindowDefaults.defaultSize)
    }

    // MARK: - NSWindowDelegate
    func windowWillStartLiveResize(_ notification: Notification) {
        liveResizeDidChange?(true)
        publishLiveResizeContentSize()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let contentHeightForWidth else {
            return frameSize
        }

        let currentContentSize = contentSize(fallback: frame.size)
        let decorationSize = CGSize(
            width: frame.width - currentContentSize.width,
            height: frame.height - currentContentSize.height
        )
        let contentWidth = (frameSize.width - decorationSize.width)
            .clamped(to: contentMinSize.width...contentMaxSize.width)
        return CGSize(
            width: contentWidth + decorationSize.width,
            height: contentHeightForWidth(contentWidth)
                .clamped(to: contentMinSize.height...contentMaxSize.height)
                + decorationSize.height
        )
    }

    func windowDidResize(_ notification: Notification) {
        if inLiveResize {
            publishLiveResizeContentSize()
        }
        else {
            publishWindowFrame()
        }
    }

    func windowDidMove(_ notification: Notification) {
        publishWindowOrigin()
    }

    /// Double-clicking the titlebar still zooms through the hidden zoom button,
    /// which would stretch the keyboard to fill the screen.
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        false
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        liveResizeDidChange?(false)
        publishWindowFrame()
    }

    // MARK: - Helpers
    private func publishWindowFrame() {
        sizeDidChange?(contentSize(fallback: contentMinSize))
        publishWindowOrigin()
    }

    private func publishLiveResizeContentSize() {
        contentSizeDidChangeDuringLiveResize?(contentSize(fallback: contentMinSize))
    }

    private func publishWindowOrigin() {
        originDidChange?(frame.origin)
    }

    private func applyDefaultCursorIfNeeded(for event: NSEvent) {
        guard event.shouldUseDefaultKeyboardWindowCursor else {
            return
        }

        if let contentView,
            contentView.bounds.contains(contentView.convert(event.locationInWindow, from: nil))
        {
            NSCursor.arrow.set()
        }
    }

    private func applyResizableBehavior(_ configuration: AlwaysOnTopWindowConfiguration) {
        let styleMask = Self.styleMask(for: configuration)
        if self.styleMask != styleMask { self.styleMask = styleMask }
        configureWindowChrome()

        if !configuration.allowsResizing || !configuration.maintainsContentAspectRatio {
            applyUnrestrictedResizeBehavior()
        }
    }

    // MARK: - Window Style
    private static func styleMask(for configuration: AlwaysOnTopWindowConfiguration)
        -> NSWindow.StyleMask
    {
        var styleMask: NSWindow.StyleMask = [.nonactivatingPanel]

        if configuration.allowsResizing {
            styleMask.formUnion([.titled, .fullSizeContentView, .resizable])
        }
        else {
            styleMask.insert(.borderless)
        }

        return styleMask
    }

    private func configureWindowChrome() {
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func applyUnrestrictedResizeBehavior() {
        contentResizeIncrements = Self.unrestrictedResizeIncrements
        resizeIncrements = Self.unrestrictedResizeIncrements
    }

    private func applyInitialPlacement(_ configuration: AlwaysOnTopWindowConfiguration) {
        let needsSizeChange =
            !isVisible || contentSize(fallback: configuration.size) != configuration.size

        if needsSizeChange {
            setFittedContentSize(
                configuration.size.validWindowConstraint(
                    fallback: FloatingWindowDefaults.defaultSize
                )
            )
        }

        if let origin = FloatingWindowDefaults.sanitizedOrigin(configuration.origin) {
            setFrameOrigin(origin)
        }
        else if frame.origin == .zero || needsSizeChange {
            center()
        }
    }

    private static func validOrigin(_ origin: CGPoint?) -> CGPoint {
        FloatingWindowDefaults.sanitizedOrigin(origin) ?? .zero
    }
}

extension NSEvent {
    // MARK: - Cursor
    fileprivate var shouldUseDefaultKeyboardWindowCursor: Bool {
        switch type {
        case .cursorUpdate,
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .mouseEntered,
            .mouseExited,
            .mouseMoved,
            .rightMouseDown,
            .rightMouseDragged,
            .rightMouseUp:
            true
        default:
            false
        }
    }
}

extension CGSize {
    // MARK: - Constraint
    fileprivate func clamped(minimumSize: CGSize, maximumSize: CGSize) -> CGSize {
        CGSize(
            width: min(max(width, minimumSize.width), maximumSize.width),
            height: min(max(height, minimumSize.height), maximumSize.height)
        )
    }
}
