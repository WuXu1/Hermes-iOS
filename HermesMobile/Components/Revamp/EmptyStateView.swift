import SwiftUI

/// Friendly placeholder for an empty list, with an optional call to action.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Design.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Design.Brand.accent.opacity(0.9))
                .padding(.bottom, Design.Spacing.xxs)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Design.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Design.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, Design.Spacing.md)
                        .padding(.vertical, Design.Spacing.xs)
                }
                .buttonStyle(.glassProminent)
                .tint(Design.Brand.accent)
                .padding(.top, Design.Spacing.xs)
            }
        }
        .padding(Design.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}
