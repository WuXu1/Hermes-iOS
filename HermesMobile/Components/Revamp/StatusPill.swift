import SwiftUI

/// A compact capsule label for task and automation states.
struct StatusPill: View {
    let label: String
    let color: Color
    var systemImage: String?

    var body: some View {
        HStack(spacing: Design.Spacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, Design.Spacing.xs)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
        .accessibilityElement(children: .combine)
    }
}
