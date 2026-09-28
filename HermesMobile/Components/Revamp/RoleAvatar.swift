import SwiftUI

/// A role's circular avatar: tinted fill, role symbol, optional live dot.
struct RoleAvatar: View {
    enum Size {
        case small, medium, large

        var diameter: CGFloat {
            switch self {
            case .small: 24
            case .medium: 36
            case .large: 56
            }
        }

        var symbolSize: CGFloat { diameter * 0.42 }
    }

    let style: RoleStyle
    var size: Size = .medium
    var isLive = false

    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(style.color.opacity(0.18))
            Circle()
                .strokeBorder(style.color.opacity(0.35), lineWidth: 1)
            Image(systemName: style.symbol)
                .font(.system(size: size.symbolSize, weight: .semibold))
                .foregroundStyle(style.color)
        }
        .frame(width: size.diameter, height: size.diameter)
        .overlay(alignment: .bottomTrailing) {
            if isLive {
                Circle()
                    .fill(Design.Colors.success)
                    .frame(width: size.diameter * 0.28, height: size.diameter * 0.28)
                    .overlay(Circle().strokeBorder(Design.Colors.canvas, lineWidth: 2))
                    .scaleEffect(pulse ? 1.0 : 0.8)
                    .opacity(pulse ? 1.0 : 0.7)
                    .onAppear {
                        withAnimation(Design.Motion.breathe) { pulse = true }
                    }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(isLive ? "\(style.displayName), working" : style.displayName)
    }
}
