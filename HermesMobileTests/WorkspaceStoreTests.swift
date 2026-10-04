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

        store.selectedRole = "coach"

        #expect(store.sections.map(\.kind) == [.needsYou, .done])
        let tasks = store.sections.flatMap(\.tasks)
        #expect(tasks.allSatisfy { $0.assignee == "coach" })
        // Badge counts ignore the filter.
        #expect(store.workingCount == 2)
    }

    @Test func rolesListDefaultFirstThenKnownOrder() async {
        let (store, _) = makeStore()
        await store.refresh()
        #expect(store.roles.map(\.name) == ["default", "developer", "tutor", "assistant", "coach"])
        #expect(store.activity(for: "assistant").isWorking)
        #expect(store.activity(for: "assistant").openCount == 2)
        #expect(!store.activity(for: "tutor").isWorking)
    }

    @Test func createAddsTaskForAssignee() async throws {
        let (store, _) = makeStore()
        await store.refresh()

        let task = try await store.create(
            KanbanTaskDraft(title: "Draft a packing list", body: "Lisbon, 3 days", assignee: "assistant")
        )

        let all = store.board.allTasks
        #expect(all.contains { $0.id == task.id && $0.status == .ready && $0.assignee == "assistant" })
        #expect(!all.contains { $0.title.hasPrefix("Review:") })
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
        await store.refresh(profile: "default")

        // Fixture times are relative to 2026-09-28 16:46 UTC.
        let now = Date(timeIntervalSince1970: 1_790_614_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let groups = store.grouped(now: now, calendar: calendar)
        #expect(groups.map(\.title) == ["Today", "This week", "Earlier"])
        #expect(groups[0].items.map(\.displayTitle) == ["Plan a weekend in Lisbon", "Quiz prep"])
        #expect(groups[2].items.map(\.displayTitle) == ["Houseplant care"])
    }

    @Test func searchFiltersTitleAndPreview() async {
        let store = ConversationsStore(api: HermesWorkspaceAPI(transport: MockWorkspaceTransport()))
        await store.refresh(profile: "default")
        let items = store.grouped(query: "quiz me").flatMap(\.items)
        #expect(items.map(\.displayTitle) == ["Quiz prep"])
    }

    @Test func listRequestIsScopedToTheAgent() async {
        let transport = MockWorkspaceTransport()
        let store = ConversationsStore(api: HermesWorkspaceAPI(transport: transport))
        await store.refresh(profile: "tutor")
        #expect(transport.lastQuery["profile"] == "tutor")
        #expect(transport.lastQuery["exclude_sources"] == "cron,subagent")
    }

    @Test func staleRefreshAfterAgentSwitchIsDropped() async {
        let transport = MockWorkspaceTransport()
        let gate = SessionsGate()
        transport.sessionsGate = gate
        let store = ConversationsStore(api: HermesWorkspaceAPI(transport: transport))
        let slow = Task { await store.refresh(profile: "developer") }
        while !(await gate.isWaiting) { await Task.yield() }

        store.agentWillSwitch()
        transport.sessionsGate = nil
        await store.refresh(profile: "coach")
        #expect(!store.sessions.isEmpty)

        store.agentWillSwitch()
        await gate.open()
        await slow.value
        #expect(store.sessions.isEmpty)
    }

    @Test func openBindsTheSessionAndNotifies() async throws {
        let transport = MockWorkspaceTransport()
        let store = ConversationsStore(api: HermesWorkspaceAPI(transport: transport))
        var switched = 0
        store.onConversationSwitched = { switched += 1 }
        await store.refresh(profile: "tutor")
        let telegram = try #require(store.sessions.first { $0.sourceLabel == "Telegram" })

        try await store.open(telegram, profile: "tutor")

        #expect(store.currentSessionID == telegram.id)
        #expect(transport.openedSessions == [.init(profile: "tutor", sessionId: telegram.id)])
        #expect(switched == 1)
    }

    @Test func startNewIsForTheSelectedAgent() async throws {
        let transport = MockWorkspaceTransport()
        let store = ConversationsStore(api: HermesWorkspaceAPI(transport: transport))
        var switched = 0
        store.onConversationSwitched = { switched += 1 }
        store.currentSessionID = "old"

        try await store.startNew(profile: "coach")

        #expect(transport.createdConversations == ["coach"])
        #expect(store.currentSessionID == nil)
        #expect(switched == 1)
    }

    @Test func renameAndArchiveGoThroughHermes() async throws {
        let transport = MockWorkspaceTransport()
        let store = ConversationsStore(api: HermesWorkspaceAPI(transport: transport))
        await store.refresh(profile: "default")
        let first = try #require(store.sessions.first)

        try await store.rename(first, to: "  Renamed  ", profile: "default")
        #expect(store.sessions.first { $0.id == first.id }?.displayTitle == "Renamed")

        try await store.archive(first, profile: "default")
        #expect(!store.sessions.contains { $0.id == first.id })
    }

    @Test func archivingTheCurrentChatStartsANewOne() async throws {
        let transport = MockWorkspaceTransport()
        let store = ConversationsStore(api: HermesWorkspaceAPI(transport: transport))
        await store.refresh(profile: "default")
        let first = try #require(store.sessions.first)
        store.currentSessionID = first.id

        try await store.archive(first, profile: "default")

        #expect(store.currentSessionID == nil)
        #expect(transport.createdConversations == ["default"])
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

    @Test func jobActionsCarryTheJobsAgent() async throws {
        let transport = MockWorkspaceTransport()
        let api = HermesWorkspaceAPI(transport: transport)
        let jobs = try await api.jobs()
        let id = try #require(jobs.first?.id)

        try await api.trigger(jobID: id, profile: "coach")
        #expect(transport.lastQuery == ["profile": "coach"])
        try await api.pause(jobID: id, profile: nil)
        #expect(transport.lastQuery == [:])
        try await api.resume(jobID: id, profile: "default")
        #expect(transport.lastQuery == [:])
    }

    @Test func libraryCallsCarryTheSelectedAgent() async {
        let transport = MockWorkspaceTransport()
        let store = LibraryStore(api: HermesWorkspaceAPI(transport: transport))
        store.profile = "tutor"
        await store.refresh()
        #expect(transport.lastQuery == ["profile": "tutor"])
    }

    @Test func lockedSkillCannotBeSwitchedOff() async {
        let transport = MockWorkspaceTransport()
        let store = LibraryStore(api: HermesWorkspaceAPI(transport: transport))
        store.setSkillsForTesting([
            HermesSkill(name: "coach", description: nil, category: nil, enabled: true, usage: nil, provenance: nil, locked: true)
        ])
        let requestsBefore = transport.requests.count

        let changed = await store.setSkill(store.skills[0], enabled: false)

        #expect(!changed)
        #expect(store.skills[0].enabled)
        #expect(transport.requests.count == requestsBefore)
    }

    @Test func slowResultForPreviousAgentIsDropped() async {
        let transport = MockWorkspaceTransport()
        let gate = SessionsGate()
        transport.memoryGate = (profile: "coach", gate: gate)
        let store = LibraryStore(api: HermesWorkspaceAPI(transport: transport))
        store.profile = "coach"
        let slow = Task { await store.refresh() }
        while !(await gate.isWaiting) { await Task.yield() }

        store.profile = "tutor"
        await store.refresh()
        let marker = HermesSkill(name: "tutor-only", description: nil, category: nil, enabled: true, usage: nil, provenance: nil, locked: true)
        store.setSkillsForTesting([marker])
        await gate.open()
        await slow.value

        #expect(store.profile == "tutor")
        #expect(store.hasLoaded)
        #expect(store.skills == [marker])
    }

    @Test func switchingAgentClearsOldDataAndSaveTargetsNewAgent() async throws {
        let transport = MockWorkspaceTransport()
        let store = LibraryStore(api: HermesWorkspaceAPI(transport: transport))
        await store.refresh()
        #expect(!store.skills.isEmpty)

        store.profile = "coach"
        #expect(store.skills.isEmpty)
        #expect(!store.hasLoaded)

        try await store.save(.user, content: "- Likes runs.\n")
        #expect(transport.lastQuery == ["profile": "coach"])
    }
}
