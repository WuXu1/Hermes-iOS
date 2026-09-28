import SwiftUI

/// Shown above cached content when the Hermes host can't be reached.
struct OfflineBanner: View {
    var message = "Hermes is offline — showing saved data"
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: Design.Spacing.xs) {
            Image(systemName: "bolt.horizontal.circle")
                .foregroundStyle(Design.Colors.warning)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Design.Colors.textSecondary)
            Spacer(minLength: 0)
            if let onRetry {
                Button("Retry", action: onRetry)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Design.Brand.accent)
            }
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Design.CornerRadius.md, style: .continuous)
                .fill(Design.Colors.warning.opacity(0.1))
        )
    }
}
