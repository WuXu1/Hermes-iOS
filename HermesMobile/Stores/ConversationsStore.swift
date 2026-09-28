import Foundation

/// Chat history: the user's conversations on the relay and switching between them.
@MainActor
@Observable
final class ConversationsStore {
    struct Group: Identifiable, Equatable {
        let title: String
        let items: [ConversationSummary]
        var id: String { title }
    }

    private(set) var conversations: [ConversationSummary] = []
    private(set) var isLoading = false
    private(set) var isOffline = false

    /// Called after the current conversation changes, so chat can reload.
    var onConversationSwitched: (@MainActor () async -> Void)?

    private let api: HermesWorkspaceAPI

    init(api: HermesWorkspaceAPI) {
        self.api = api
    }

    var current: ConversationSummary? { conversations.first(where: \.isCurrent) }

    func grouped(query: String = "", now: Date = Date(), calendar: Calendar = .current) -> [Group] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let matches = conversations.filter { conversation in
            needle.isEmpty
                || conversation.title.localizedCaseInsensitiveContains(needle)
                || conversation.preview.localizedCaseInsensitiveContains(needle)
        }
        var today: [ConversationSummary] = []
        var week: [ConversationSummary] = []
        var earlier: [ConversationSummary] = []
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        for conversation in matches {
            let date = conversation.lastMessageAt ?? .distantPast
            if calendar.isDate(date, inSameDayAs: now) {
                today.append(conversation)
            } else if date > weekAgo {
                week.append(conversation)
            } else {
                earlier.append(conversation)
            }
        }
        return [Group(title: "Today", items: today), Group(title: "This week", items: week), Group(title: "Earlier", items: earlier)]
            .filter { !$0.items.isEmpty }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            conversations = try await api.conversations()
            isOffline = false
        } catch {
            isOffline = true
        }
    }

    func reset() {
        conversations = []
        isOffline = false
    }

    func startNew() async throws {
        _ = try await api.newConversation()
        await refresh()
        await onConversationSwitched?()
    }

    func activate(_ conversation: ConversationSummary) async throws {
        guard !conversation.isCurrent else { return }
        try await api.activateConversation(id: conversation.id)
        await refresh()
        await onConversationSwitched?()
    }

    func rename(_ conversation: ConversationSummary, to title: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await api.renameConversation(id: conversation.id, title: trimmed)
        await refresh()
    }

    func archive(_ conversation: ConversationSummary) async throws {
        try await api.archiveConversation(id: conversation.id)
        await refresh()
        if conversation.isCurrent {
            await onConversationSwitched?()
        }
    }
}
