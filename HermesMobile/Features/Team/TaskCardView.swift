import SwiftUI

/// One task on the board: who owns it, where it stands, the latest word from the worker.
struct TaskCardView: View {
    let task: KanbanTask

    var body: some View {
        let style = RoleStyle.forProfile(task.assignee)
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            RoleAvatar(style: style, size: .medium, isLive: task.status == .running)
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Design.Spacing.xs) {
                    task.status.pill
                    Text(metaLine(style: style))
                        .font(.caption)
                        .foregroundStyle(Design.Colors.textTertiary)
                        .lineLimit(1)
                }
                if let headline = task.headline {
                    Text(headline)
                        .font(.subheadline)
                        .foregroundStyle(task.status == .blocked ? Design.Colors.warning.opacity(0.9) : Design.Colors.textSecondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .overlay {
            if task.status == .running {
                LiveBorder(color: style.color)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func metaLine(style: RoleStyle) -> String {
        let when: String
        switch task.status {
        case .running: when = "started \(RelativeTime.short(task.startedAt ?? task.createdAt))"
        case .done: when = "finished \(RelativeTime.short(task.completedAt))"
        default: when = RelativeTime.short(task.createdAt)
        }
        return [style.displayName, when].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// A slow light sweeping around a card's border while its task is running.
private struct LiveBorder: View {
    let color: Color
    @State private var angle: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: Design.CornerRadius.lg, style: .continuous)
            .strokeBorder(
                AngularGradient(
                    colors: [color.opacity(0), color.opacity(0.55), color.opacity(0)],
                    center: .center,
                    angle: .degrees(angle)
                ),
                lineWidth: 1.2
            )
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}
