import Foundation

enum HermesMemoryKind: String, CaseIterable, Identifiable, Sendable {
    case user
    case memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .user: "About you"
        case .memory: "Hermes's notes"
        }
    }

    var subtitle: String {
        switch self {
        case .user: "What Hermes knows about you and your preferences"
        case .memory: "Facts and conventions Hermes has learned while working"
        }
    }

    var symbol: String {
        switch self {
        case .user: "person.text.rectangle"
        case .memory: "note.text"
        }
    }

    /// Hermes's built-in memory file limit is enforced by the connector.
    static let maxBytes = 64 * 1024
}

struct HermesMemoryDocument: Decodable, Equatable, Sendable {
    var content: String
    var updatedAtUnix: Double?

    enum CodingKeys: String, CodingKey {
        case content
        case updatedAtUnix = "updatedAt"
    }

    var updatedAt: Date? { HermesDate.fromUnix(updatedAtUnix) }
}

struct HermesMemory: Decodable, Equatable, Sendable {
    var memory: HermesMemoryDocument
    var user: HermesMemoryDocument

    subscript(kind: HermesMemoryKind) -> HermesMemoryDocument {
        get { kind == .user ? user : memory }
        set {
            if kind == .user { user = newValue } else { memory = newValue }
        }
    }

    static let empty = HermesMemory(
        memory: HermesMemoryDocument(content: "", updatedAtUnix: nil),
        user: HermesMemoryDocument(content: "", updatedAtUnix: nil)
    )
}

struct MemoryWrite: Encodable, Sendable {
    var content: String
}

struct HermesSkill: Decodable, Identifiable, Hashable, Sendable {
    var name: String
    var description: String?
    var category: String?
    var enabled: Bool
    var usage: Int?
    var provenance: String?

    var id: String { name }

    var categoryTitle: String {
        guard let category, !category.isEmpty else { return "Other" }
        return category
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
            .replacingOccurrences(of: "Ai ", with: "AI ")
    }
}

struct SkillContent: Decodable, Sendable {
    var name: String
    var content: String
}

struct SkillToggle: Encodable, Sendable {
    var name: String
    var enabled: Bool
}
