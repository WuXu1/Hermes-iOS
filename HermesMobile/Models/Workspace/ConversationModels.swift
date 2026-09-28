import Foundation

struct ConversationSummary: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var preview: String
    var lastMessageAt: Date?
    var isCurrent: Bool
}

struct ConversationsResponse: Decodable, Sendable {
    var conversations: [ConversationSummary]
}

struct ConversationResponse: Decodable, Sendable {
    var conversation: ConversationSummary
}

struct ConversationRename: Encodable, Sendable {
    var title: String
}
