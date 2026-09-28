import SwiftUI

/// Visual identity for a Hermes profile (a team role): color, symbol and name.
/// Shared by avatars, task cards and pills so a role looks the same everywhere.
struct RoleStyle: Equatable {
    let name: String
    let displayName: String
    let color: Color
    let symbol: String

    static let defaultProfileName = "default"

    /// Colors for roles without a fixed style, picked by a stable hash of the name.
    static let palette: [Color] = [
        Color(hex: 0x64D2FF),
        Color(hex: 0xFFD60A),
        Color(hex: 0x30D158),
        Color(hex: 0xBF5AF2),
        Color(hex: 0xFF9F0A),
        Color(hex: 0x5E5CE6),
        Color(hex: 0xFF6482),
        Color(hex: 0x66D4CF),
    ]

    private static let known: [String: RoleStyle] = [
        defaultProfileName: RoleStyle(
            name: defaultProfileName,
            displayName: "Chief of staff",
            color: Design.Brand.accent,
            symbol: "sparkles"
        ),
        "researcher": RoleStyle(
            name: "researcher",
            displayName: "Researcher",
            color: Color(hex: 0x5AC8FA),
            symbol: "magnifyingglass"
        ),
        "operator": RoleStyle(
            name: "operator",
            displayName: "Operator",
            color: Color(hex: 0x34C759),
            symbol: "safari"
        ),
        "coder": RoleStyle(
            name: "coder",
            displayName: "Coder",
            color: Color(hex: 0xAF7BFF),
            symbol: "chevron.left.forwardslash.chevron.right"
        ),
        "reviewer": RoleStyle(
            name: "reviewer",
            displayName: "Reviewer",
            color: Color(hex: 0xFF7A6B),
            symbol: "checkmark.seal"
        ),
    ]

    static let unassigned = RoleStyle(
        name: "",
        displayName: "Unassigned",
        color: Design.Colors.textTertiary,
        symbol: "person.crop.circle.badge.questionmark"
    )

    static func forProfile(_ name: String?) -> RoleStyle {
        guard let name, !name.isEmpty else { return unassigned }
        if let style = known[name] { return style }
        return RoleStyle(
            name: name,
            displayName: humanize(name),
            color: palette[paletteIndex(for: name)],
            symbol: "person.fill"
        )
    }

    /// FNV-1a over the UTF-8 bytes; unlike `hashValue` it is stable across launches.
    static func paletteIndex(for name: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in name.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % UInt32(palette.count))
    }

    private static func humanize(_ name: String) -> String {
        let words = name.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let first = words.first else { return name }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst()).joined(separator: " ")
    }
}
