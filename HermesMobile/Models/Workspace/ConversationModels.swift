import Foundation

struct HermesSessionSummary: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String?
    var source: String?
    var preview: String?
    var lastActiveUnix: Double?
    var messageCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, source, preview
        case lastActiveUnix = "last_active"
        case messageCount = "message_count"
    }

    var lastActive: Date? { HermesDate.fromUnix(lastActiveUnix) }
    var displayTitle: String {
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New chat" : trimmed
    }

    var sourceLabel: String? {
        switch source {
        case "telegram": "Telegram"
        case "desktop", "cli": "Mac app"
        case "tool", "oneshot": "App"
        default: nil
        }
    }
}

struct HermesSessionsResponse: Decodable, Sendable {
    var sessions: [HermesSessionSummary]
}

struct SessionPatch: Encodable, Sendable {
    var title: String?
    var archived: Bool?
}

struct ConversationOpen: Encodable, Sendable {
    var profile: String
    var sessionId: String
}

struct ConversationCreate: Encodable, Sendable {
    var profile: String
}
