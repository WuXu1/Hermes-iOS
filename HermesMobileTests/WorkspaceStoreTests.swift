import Foundation
import Testing
@testable import HermesMobile

@MainActor
struct TeamStoreTests {
    private func makeStore(mode: MockWorkspaceTransport.Mode = .online) -> (TeamStore, MockWorkspaceTransport) {
        let transport = MockWorkspaceTransport(mode: mode)
        return (TeamStore(api: HermesWorkspaceAPI(transport: transport)), transport)
    }

    @Test func sectionsGroupAndOrderTasks() async {
        let (store, _) = makeStore()
        await store.refresh()

        #expect(store.sections.map(\.kind) == [.needsYou, .working, .upNext, .review, .done])
        #expect(store.sections.first { $0.kind == .needsYou }?.tasks.map(\.id) == ["t_blk7c21"])
        #expect(Set(store.sections.first { $0.kind == .working }?.tasks.map(\.id) ?? []) == ["t_run41a9", "t_run88f0"])
        // Up next: waiting and queued work, oldest first within the same priority.
        #expect(store.sections.first { $0.kind == .upNext }?.tasks.map(\.id) == ["t_todo5b2", "t_rdy9e41"])
        // Done: most recently completed first.
        #expect(store.sections.first { $0.kind == .done }?.tasks.first?.id == "t_don0a17")
        #expect(store.needsYouCount == 1)
        #expect(store.workingCount == 2)
    }

    @Test func roleFilterNarrowsSectionsAndDropsEmptyOnes() async {
        let (store, _) = makeStore()
        await store.refresh()

        store.selectedRole = "operator"

        #expect(store.sections.map(\.kind) == [.needsYou, .done])
        let tasks = store.sections.flatMap(\.tasks)
        #expect(tasks.allSatisfy { $0.assignee == "operator" })
        // Badge counts ignore the filter.
        #expect(store.workingCount == 2)
    }

    @Test func rolesListDefaultFirstThenKnownOrder() async {
        let (store, _) = makeStore()
        await store.refresh()
        #expect(store.roles.map(\.name) == ["default", "researcher", "operator", "coder", "reviewer"])
        #expect(store.activity(for: "researcher").isWorking)
        #expect(store.activity(for: "researcher").openCount == 2)
        #expect(!store.activity(for: "reviewer").isWorking)
    }

    @Test func createWithReviewAddsLinkedReviewerTask() async throws {
        let (store, _) = makeStore()
        await store.refresh()

        let task = try await store.create(
            KanbanTaskDraft(title: "Draft a packing list", body: "Lisbon, 3 days", assignee: "researcher"),
            reviewAfter: true
        )

        let all = store.board.allTasks
        #expect(all.contains { $0.id == task.id && $0.status == .ready })
        let review = try #require(all.first { $0.title == "Review: Draft a packing list" })
        #expect(review.assignee == "reviewer")
        #expect(review.status == .todo)
    }

    @Test func replyUnblocksBlockedTask() async throws {
        let (store, _) = makeStore()
        await store.refresh()
        let blocked = try #require(store.board.allTasks.first { $0.status == .blocked })

        try await store.reply(to: blocked, with: "Signed in — try again.")

        #expect(store.board.allTasks.first { $0.id == blocked.id }?.status == .ready)
        let detail = try await store.detail(for: blocked.id)
        #expect(detail.comments.last?.body == "Signed in — try again.")
    }

    @Test func offlineRefreshKeepsDataAndFlagsOffline() async {
        let (store, transport) = makeStore()
        await store.refresh()
        let count = store.board.allTasks.count

        transport.mode = .offline
        await store.refresh()

        #expect(store.isOffline)
        #expect(store.board.allTasks.count == count)
    }
}

@MainActor
struct ConversationsStoreTests {
    @Test func groupsByRecency() async {
        let transport = MockWorkspaceTransport()
        let store = ConversationsStore(api: HermesWorkspaceAPI(transport: transport))
        await store.refresh()

        // Fixture times are relative to 2026-09-28 16:46 UTC.
        let now = Date(timeIntervalSince1970: 1_790_614_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let groups = store.grouped(now: now, calendar: calendar)
        #expect(groups.map(\.title) == ["Today", "This week", "Earlier"])
        #expect(groups[0].items.map(\.title) == ["Plan a weekend in Lisbon", "Monitor for photo editing"])
        #expect(groups[2].items.map(\.title) == ["Houseplant care"])
    }

    @Test func searchFiltersTitleAndPreview() async {
        let store = ConversationsStore(api: HermesWorkspaceAPI(transport: MockWorkspaceTransport()))
        await store.refresh()
        let items = store.grouped(query: "coder").flatMap(\.items)
        #expect(items.map(\.title) == ["Bank CSV cleanup"])
    }

    @Test func startNewMakesItCurrentAndNotifies() async throws {
        let store = ConversationsStore(api: HermesWorkspaceAPI(transport: MockWorkspaceTransport()))
        var switched = 0
        store.onConversationSwitched = { switched += 1 }
        await store.refresh()

        try await store.startNew()

        #expect(store.current?.title == "New chat")
        #expect(switched == 1)
    }
}

@MainActor
struct LibraryAndAutomationsStoreTests {
    @Test func skillToggleIsOptimisticAndPersists() async throws {
        let store = LibraryStore(api: HermesWorkspaceAPI(transport: MockWorkspaceTransport()))
        await store.refresh()
        let docx = try #require(store.skills.first { $0.name == "docx" })
        #expect(!docx.enabled)

        await store.setSkill(docx, enabled: true)

        #expect(store.skills.first { $0.name == "docx" }?.enabled == true)
    }

    @Test func skillsGroupByCategoryAndSearch() async {
        let store = LibraryStore(api: HermesWorkspaceAPI(transport: MockWorkspaceTransport()))
        await store.refresh()
        store.skillQuery = "pdf"
        #expect(store.skillsByCategory.map(\.title) == ["Documents"])
        #expect(store.skillsByCategory.first?.skills.map(\.name) == ["pdf"])
    }

    @Test func savingMemoryUpdatesDocument() async throws {
        let store = LibraryStore(api: HermesWorkspaceAPI(transport: MockWorkspaceTransport()))
        await store.refresh()
        try await store.save(.user, content: "- Prefers tea.\n")
        #expect(store.memory[.user].content == "- Prefers tea.\n")
    }

    @Test func automationsPauseAndCreate() async throws {
        let store = AutomationsStore(api: HermesWorkspaceAPI(transport: MockWorkspaceTransport()))
        await store.refresh()
        let first = try #require(store.jobs.first)
        #expect(!first.isPaused)

        try await store.togglePause(first)
        #expect(store.jobs.first { $0.id == first.id }?.isPaused == true)

        try await store.create(
            CronJobDraft(name: "Stretch", prompt: "Remind me to stretch", schedule: CronSchedulePreset.hourly.expression),
            profile: "default"
        )
        #expect(store.jobs.contains { $0.name == "Stretch" })
        #expect(store.blueprints.count == 4)
    }
}
