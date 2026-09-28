import SwiftUI

// MARK: - Design Tokens
// All visual constants for HermesMobile. No magic numbers in view code.

enum Design {

    // MARK: - Brand

    enum Brand {
        /// Hermes amber. Use sparingly: primary actions, live states, focus.
        static let accent = Color(hex: 0xFFBF00)
        static let accentGradient = LinearGradient(
            colors: [accent, accent.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Colors

    enum Colors {
        // Semantic tokens. Views should use these; the aliases below keep
        // older screens compiling.

        /// App background: layered near-black.
        static let canvas = Color(hex: 0x0B0B0D)
        /// Solid card surface on the canvas.
        static let surfaceSolid = Color(hex: 0x16161A)
        /// Raised surface: user message pills, inputs, selected rows.
        static let surfaceRaised = Color(hex: 0x1E1E23)
        /// Hairline borders and dividers.
        static let hairline = Color.white.opacity(0.06)
        static let textPrimary = Color(hex: 0xF5F5F2)
        static let textSecondary = textPrimary.opacity(0.7)
        static let textTertiary = textPrimary.opacity(0.45)
        static let success = Color(hex: 0x34C759)
        static let warning = Color(hex: 0xFFB020)
        static let danger = Color(hex: 0xFF5A52)

        // Aliases for the original token names.

        static let background = canvas
        static let foreground = textPrimary
        static let secondaryForeground = textSecondary
        /// Translucent surface for glass-adjacent elements.
        static let surface = Color.white.opacity(0.08)
        static let divider = hairline
    }

    // MARK: - Spacing (4pt base grid)

    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }

    // MARK: - Corner Radii

    enum CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
        static let full: CGFloat = .infinity
    }

    // MARK: - Typography

    enum Typography {
        static let heroTitle: Font = .largeTitle.bold()
        static let screenTitle: Font = .title.bold()
        static let screenTitle2: Font = .title2.bold()
        static let sectionTitle: Font = .title3.bold()
        static let headline: Font = .headline
        static let body: Font = .body
        static let callout: Font = .callout
        static let footnote: Font = .footnote
        static let caption: Font = .caption
        static let caption2: Font = .caption2
    }

    // MARK: - Animation

    enum Motion {
        static let quickResponse: Animation = .spring(response: 0.25, dampingFraction: 0.8)
        static let standard: Animation = .spring(response: 0.35, dampingFraction: 0.75)
        static let expressive: Animation = .spring(response: 0.5, dampingFraction: 0.7)
        static let gentle: Animation = .spring(response: 0.6, dampingFraction: 0.85)
        static let pulse: Animation = .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
        static let breathe: Animation = .easeInOut(duration: 2.0).repeatForever(autoreverses: true)
    }

    // MARK: - Size

    enum Size {
        static let minTapTarget: CGFloat = 44
        static let iconTiny: CGFloat = 10
        static let iconSmall: CGFloat = 16
        static let iconMedium: CGFloat = 24
        static let iconLarge: CGFloat = 32
        static let iconXL: CGFloat = 40
        static let iconHero: CGFloat = 60
        static let avatarSmall: CGFloat = 32
        static let avatarMedium: CGFloat = 48
        static let avatarLarge: CGFloat = 80
        static let thumbnailSmall: CGFloat = 64
        static let thumbnailMedium: CGFloat = 120
        static let thumbnailLarge: CGFloat = 200
        static let heroHeight: CGFloat = 300
        static let cardMinHeight: CGFloat = 160
        static let badgeSize: CGFloat = 22
        static let inputBarHeight: CGFloat = 52
        static let voiceOrbSize: CGFloat = 140
        static let glassCircleButton: CGFloat = 40
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
