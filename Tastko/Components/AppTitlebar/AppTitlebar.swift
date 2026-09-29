import SwiftUI

// MARK: - AppTitlebar
struct AppTitlebar<TitleContent: View>: View {
    @Environment(\.floatingWindowController) private var floatingWindowController
    @Environment(\.keyboardPalette) private var palette
    let close: () -> Void
    let minimize: () -> Void
    let titleContent: TitleContent

    // MARK: - Initialization
    init(
        close: @escaping () -> Void,
        minimize: @escaping () -> Void,
        @ViewBuilder titleContent: () -> TitleContent
    ) {
        self.close = close
        self.minimize = minimize
        self.titleContent = titleContent()
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            HStack(spacing: KeyboardDesign.Metrics.rowSpacing) {
                HStack(spacing: 2) {
                    AppTitlebarWindowButton(kind: .close, action: close)
                    AppTitlebarWindowButton(kind: .minimize, action: minimize)
                }
                .disabled(floatingWindowController.isScreenLocked)

                Spacer(minLength: 16)

                #if DEBUG
                    KeyboardDebugWindowToggleButton()
                #endif
                AppUpdateButton()
                SystemAccessibilityKeyboardButton()
                AccessibilityStatusButton()
            }

            titleContent
                .font(KeyboardDesign.Typography.title)
                .foregroundStyle(palette.label)
                .padding(.horizontal, 112)
        }
        .font(KeyboardDesign.Typography.toolbar)
        .buttonStyle(.titlebar)
        .padding(.leading, KeyboardDesign.Metrics.panelInset + KeyboardDesign.Metrics.keyInset)
        .padding(.trailing, KeyboardDesign.Metrics.rowInset)
        .frame(height: AppConstants.titlebarHeight)
        .background {
            LinearGradient(
                colors: [palette.chrome, palette.chassis],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - AppTitlebarWindowButton
private struct AppTitlebarWindowButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let kind: AppTitlebarWindowButtonKind
    let action: () -> Void

    // MARK: - Body
    var body: some View {
        Button(kind.accessibilityLabel, systemImage: kind.symbolName, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(SubtleIconButtonStyle())
            .opacity(isEnabled ? 1 : 0.4)
            .accessibilityLabel(kind.accessibilityLabel)
            .help(kind.accessibilityLabel)
    }
}

// MARK: - AppTitlebarWindowButtonKind
private enum AppTitlebarWindowButtonKind {
    case close
    case minimize

    var symbolName: String {
        switch self {
        case .close:
            "xmark"
        case .minimize:
            "minus"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .close:
            "Close"
        case .minimize:
            "Minimize"
        }
    }
}
