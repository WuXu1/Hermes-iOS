import SwiftUI

/// Horizontal strip of role avatars. Tap filters the board; long-press opens the role.
struct RoleStripView: View {
    let roles: [HermesProfile]
    let selectedRole: String?
    let activity: (String) -> (isWorking: Bool, openCount: Int)
    let onSelect: (String?) -> Void
    let onOpenRole: (HermesProfile) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Spacing.md) {
                ForEach(roles) { profile in
                    item(for: profile)
                }
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.xxs)
        }
    }

    private func item(for profile: HermesProfile) -> some View {
        let style = RoleStyle.forProfile(profile.name)
        let state = activity(profile.name)
        let isSelected = selectedRole == profile.name
        let isDimmed = selectedRole != nil && !isSelected

        return VStack(spacing: Design.Spacing.xs) {
            RoleAvatar(style: style, size: .large, isLive: state.isWorking)
                .overlay(
                    Circle()
                        .strokeBorder(style.color, lineWidth: isSelected ? 2 : 0)
                        .padding(-4)
                )
                .overlay(alignment: .topTrailing) {
                    if state.openCount > 0 {
                        Text("\(state.openCount)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Design.Colors.canvas)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(style.color))
                            .offset(x: 4, y: -4)
                    }
                }
            Text(profile.isDefault ? "Chief" : style.displayName)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Design.Colors.textPrimary : Design.Colors.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 68)
        .opacity(isDimmed ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Design.Motion.quickResponse) {
                onSelect(isSelected ? nil : profile.name)
            }
        }
        .onLongPressGesture { onOpenRole(profile) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(style.displayName), \(state.openCount) open task\(state.openCount == 1 ? "" : "s")\(state.isWorking ? ", working" : "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Filters the board. Long-press for role details.")
        .accessibilityAction(named: "Role details") { onOpenRole(profile) }
        .accessibilityIdentifier("team.role.\(profile.name)")
    }
}
