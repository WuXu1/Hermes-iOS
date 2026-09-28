import SwiftUI

/// The app background: near-black canvas with a soft amber glow at the top.
struct CanvasBackground: View {
    var glowOpacity: Double = 0.12

    var body: some View {
        ZStack(alignment: .top) {
            Design.Colors.canvas
            RadialGradient(
                colors: [Design.Brand.accent.opacity(glowOpacity), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 420
            )
            .frame(height: 420)
            .offset(y: -120)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func canvasBackground(glowOpacity: Double = 0.12) -> some View {
        background(CanvasBackground(glowOpacity: glowOpacity))
    }

    /// Solid card surface with a hairline border, for readable content blocks.
    func cardSurface(cornerRadius: CGFloat = Design.CornerRadius.lg) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Design.Colors.surfaceSolid)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Design.Colors.hairline, lineWidth: 1)
        )
    }
}
