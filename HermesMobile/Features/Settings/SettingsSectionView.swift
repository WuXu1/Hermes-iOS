import SwiftUI

struct SettingsSectionView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text(title)
                .font(Design.Typography.footnote.weight(.semibold))
                .foregroundStyle(Design.Colors.textTertiary)
                .textCase(.uppercase)
                .padding(.leading, Design.Spacing.xxs)

            VStack(spacing: 0) {
                content
            }
            .padding(Design.Spacing.md)
            .frame(maxWidth: .infinity)
            .cardSurface()
        }
    }
}
