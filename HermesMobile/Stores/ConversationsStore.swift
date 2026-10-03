import Foundation

/// Chat history for one agent: its Hermes sessions, including Telegram and Mac app chats.
@MainActor
@Observable
final class ConversationsStore {
    struct Group: Identifiable, Equatable {
        let title: String
        let items: [HermesSessionSummary]
        var id: String { title }
    }

    private(set) var sessions: [HermesSessionSummary] = []
    private(set) var isLoading = false
    private(set) var isOffline = false
    var currentSessionID: String?

    /// Called after the current conversation changes, so chat can reload.
    var onConversationSwitched: (@MainActor () async -> Void)?

    private let api: HermesWorkspaceAPI

    init(api: HermesWorkspaceAPI) {
        self.api = api
    }

    func grouped(query: String = "", now: Date = Date(), calendar: Calendar = .current) -> [Group] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let matches = sessions.filter { session in
            needle.isEmpty
                || session.displayTitle.localizedCaseInsensitiveContains(needle)
                || (session.preview ?? "").localizedCaseInsensitiveContains(needle)
        }
        var today: [HermesSessionSummary] = []
        var week: [HermesSessionSummary] = []
        var earlier: [HermesSessionSummary] = []
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        for session in matches {
            let date = session.lastActive ?? .distantPast
            if calendar.isDate(date, inSameDayAs: now) {
                today.append(session)
            } else if date > weekAgo {
                week.append(session)
            } else {
                earlier.append(session)
            }
        }
        return [Group(title: "Today", items: today), Group(title: "This week", items: week), Group(title: "Earlier", items: earlier)]
            .filter { !$0.items.isEmpty }
    }

    func refresh(profile: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await api.sessions(profile: profile)
            isOffline = false
        } catch {
            isOffline = true
        }
    }

    func reset() {
        sessions = []
        currentSessionID = nil
        isOffline = false
    }

    func startNew(profile: String) async throws {
        try await api.newConversation(profile: profile)
        currentSessionID = nil
        await onConversationSwitched?()
    }

    func open(_ session: HermesSessionSummary, profile: String) async throws {
        guard session.id != currentSessionID else { return }
        try await api.openSession(profile: profile, id: session.id)
        currentSessionID = session.id
        await onConversationSwitched?()
    }

    func rename(_ session: HermesSessionSummary, to title: String, profile: String) async throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await api.renameSession(id: session.id, title: trimmed, profile: profile)
        await refresh(profile: profile)
    }

    func archive(_ session: HermesSessionSummary, profile: String) async throws {
        try await api.archiveSession(id: session.id, profile: profile)
        await refresh(profile: profile)
        if session.id == currentSessionID {
            try await startNew(profile: profile)
        }
    }
}
