import SwiftUI

// MARK: - FunctionToolbarView
struct FunctionToolbarView: View {
    let scale: CGFloat
    @Environment(\.keyboardService) private var keyboardService
    @Environment(\.keyInputController) private var input

    // MARK: - Body
    var body: some View {
        HStack(spacing: 4 * scale) {
            ForEach(
                FunctionToolbarItem.items(
                    functionIsActive: keyboardService.effectiveModifiers.contains(.function)
                )
            ) { item in
                Button {
                    input.press(item)
                } label: {
                    if let symbol = item.symbol {
                        Image(systemName: symbol)
                    }
                    else {
                        Text(item.title)
                    }
                }
                .buttonStyle(
                    .keycap(
                        scale: scale,
                        fillsWidth: true,
                        isExternallyPressed: item.isPressed(
                            in: keyboardService.physicalKeyboard.snapshot
                        )
                    )
                )
                .help(item.title)
                .accessibilityLabel(item.title)
                .accessibilityIdentifier("function-toolbar-\(item.id)")
            }
        }
        .padding(.horizontal, KeyboardDesign.Metrics.panelInset + KeyboardDesign.Metrics.keyInset)
        .padding(.vertical, KeyboardDesign.Metrics.functionToolbarVerticalInset * scale)
    }
}
