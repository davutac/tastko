import SwiftUI

// MARK: - AppearanceOptionCard
/// A selectable card with a visual preview above its title.
struct AppearanceOptionCard<Preview: View>: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let preview: Preview

    // MARK: - Body
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity)
                    .frame(height: 84)
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    }

                VStack(spacing: 1) {
                    Text(title)
                        .font(.callout)
                        .fontWeight(isSelected ? .semibold : .regular)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
