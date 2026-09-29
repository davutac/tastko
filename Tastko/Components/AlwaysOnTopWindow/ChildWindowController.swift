import SwiftUI

// MARK: - Child Window Controller
@MainActor
final class ChildWindowController {
    let panel: AlwaysOnTopPanel
    private let host: MouseInteractiveHostingView<AnyView>
    private let dimensions = WindowDimensions()
    private var contentSize = CGSize(width: 1, height: 1)
    private var configuration: ChildWindowConfiguration
    private(set) var isPresented = true
    private var mousePassthrough: WindowMousePassthrough?

    // MARK: - Initialization
    init(configuration: ChildWindowConfiguration, content: AnyView) {
        self.configuration = configuration
        panel = AlwaysOnTopPanel(
            configuration: .init(
                minSize: CGSize(width: 1, height: 1),
                isMovableByWindowBackground: false,
                allowsResizing: false
            )
        )
        host = MouseInteractiveHostingView(rootView: AnyView(EmptyView()))
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.autoresizingMask = [.width, .height]
        let container = NSView(frame: panel.frame)
        container.addSubview(host)
        panel.contentView = container
        update(configuration: configuration, content: content)
    }

    // MARK: - Content and Style
    func update(configuration: ChildWindowConfiguration, content: AnyView) {
        self.configuration = configuration
        isPresented = true
        let style = configuration.style
        let fitsContentWidth: Bool
        let fitsContentHeight: Bool
        switch configuration.size {
        case .content, .parentWidth(height: nil):
            (fitsContentWidth, fitsContentHeight) = (true, true)
        case .contentWidth: (fitsContentWidth, fitsContentHeight) = (true, false)
        default: (fitsContentWidth, fitsContentHeight) = (false, false)
        }
        panel.title = configuration.title
        panel.hasShadow = style.hasShadow
        panel.alphaValue = style.opacity.isFinite ? min(1, max(0, style.opacity)) : 1
        panel.ignoresMouseEvents = configuration.ignoresMouseEvents
        if !configuration.passesThroughEmptyArea || configuration.ignoresMouseEvents {
            mousePassthrough = nil
        }
        host.rootView = AnyView(
            content
                .environment(\.windowDimensions, dimensions)
                .fixedSize(horizontal: fitsContentWidth, vertical: fitsContentHeight)
                .padding(style.contentInsets)
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { [weak self] size in
                    guard fitsContentWidth, size.width.isFinite, size.height.isFinite,
                        size.width > 0, size.height > 0
                    else { return }
                    Task { @MainActor [weak self] in
                        guard let self, self.contentSize != size else { return }
                        self.contentSize = size
                        if let parent = self.panel.parent { self.synchronize(with: parent) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(style.background)
                .clipShape(.rect(cornerRadius: max(0, style.cornerRadius)))
                .overlay {
                    RoundedRectangle(cornerRadius: max(0, style.cornerRadius))
                        .strokeBorder(style.borderColor, lineWidth: max(0, style.borderWidth))
                        .allowsHitTesting(false)
                }
        )
    }

    // MARK: - Lifecycle
    func synchronize(with parent: NSWindow) {
        guard isPresented, parent.isVisible else { return }
        panel.level = parent.level
        panel.collectionBehavior = parent.collectionBehavior
        panel.hidesOnDeactivate = parent.hidesOnDeactivate
        if panel.parent !== parent { parent.addChildWindow(panel, ordered: .above) }
        dimensions.parentSize = parent.frame.size
        let frame = configuration.frame(relativeTo: parent.frame, contentSize: contentSize)
        panel.setFrame(frame, display: true)
        host.frame = CGRect(origin: .zero, size: frame.size)
        dimensions.size = frame.size
        if !panel.isVisible { panel.orderFrontRegardless() }
        if configuration.passesThroughEmptyArea && !configuration.ignoresMouseEvents {
            if mousePassthrough == nil {
                mousePassthrough = WindowMousePassthrough(panel: panel, content: host)
            }
            mousePassthrough?.update()
        }
    }

    func hide(preservingPresentation: Bool = false) {
        if !preservingPresentation { isPresented = false }
        mousePassthrough = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }
}
