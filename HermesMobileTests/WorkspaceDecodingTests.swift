import Foundation
import Testing
@testable import HermesMobile

@MainActor
struct WorkspaceDecodingTests {
    private func fixture<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        let value: T? = MockWorkspaceTransport.load(name, bundle: .main)
        return try #require(value, "fixture \(name).json should decode as \(T.self)")
    }

    @Test func boardDecodesEveryStatusColumn() throws {
        let board = try fixture("board", as: KanbanBoard.self)
        #expect(board.columns.map(\.name).contains("blocked"))
        let blocked = try #require(board.allTasks.first { $0.status == .blocked })
        #expect(blocked.assignee == "operator")
        #expect(blocked.headline?.hasPrefix("Needs you") == true)
        #expect(blocked.createdAt != nil)
    }

    @Test func unknownStatusFallsBackToUnknown() {
        #expect(KanbanStatus(apiValue: "parked") == .unknown)
        #expect(KanbanStatus(apiValue: "running") == .running)
    }

    @Test func taskDetailDecodesAttachmentsRunsAndEvents() throws {
        let detail = try fixture("task_detail", as: KanbanTaskDetail.self)
        #expect(detail.task.status == .review)
        #expect(detail.attachments.map(\.filename) == ["clean_bank_csv.py", "sample-output.md"])
        let allText = detail.attachments.allSatisfy(\.isText)
        #expect(allText)
        #expect(detail.runs.first?.profile == "coder")
        #expect(detail.events.first?.payload?["assignee"]?.stringValue == "coder")
    }

    @Test func detailToleratesMissingCollections() throws {
        let json = #"{"task": {"id": "t_1", "title": "x", "status": "ready"}}"#
        let detail = try RelayCoders.makeDecoder().decode(KanbanTaskDetail.self, from: Data(json.utf8))
        #expect(detail.comments.isEmpty && detail.runs.isEmpty)
    }

    @Test func cronJobsParseMicrosecondDates() throws {
        let jobs = try fixture("cron_jobs", as: [CronJob].self)
        #expect(jobs.count == 3)
        #expect(jobs[0].nextRunAt != nil)
        #expect(jobs[0].scheduleText == "Every day at 08:00")
        #expect(jobs[2].isPaused)
        #expect(HermesDate.parse("2026-09-28T16:45:35.226303+00:00") != nil)
    }

    @Test func blueprintFieldsDecode() throws {
        let blueprints = try fixture("cron_blueprints", as: CronBlueprintsResponse.self).blueprints
        let news = try #require(blueprints.first { $0.key == "news-digest" })
        #expect(news.fields.map(\.type) == ["text", "time", "weekdays"])
        #expect(news.fields[2].isChoice)
        let hasDelivery = blueprints[0].fields.contains { $0.isDelivery }
        #expect(hasDelivery)
    }

    @Test func cronRunOutputIsFinalAssistantReply() throws {
        let messages = try fixture("session_messages", as: SessionMessagesResponse.self)
        #expect(messages.finalReply?.hasPrefix("**Good morning.**") == true)
        let runs = try fixture("cron_runs", as: CronRunsResponse.self).runs
        #expect(runs.first?.succeeded == true)
    }

    @Test func libraryFixturesDecode() throws {
        let memory = try fixture("memory", as: HermesMemory.self)
        #expect(memory[.user].content.contains("London"))
        #expect(memory[.memory].updatedAt != nil)
        let skills = try fixture("skills", as: [HermesSkill].self)
        let hasDisabled = skills.contains { !$0.enabled }
        #expect(hasDisabled)
        #expect(skills.first { $0.name == "claude-code" }?.categoryTitle == "Autonomous AI Agents")
    }

    @Test func statusFixturesDecode() throws {
        #expect(try fixture("model_info", as: HermesModelInfo.self).effectiveContextLength == 1_000_000)
        #expect(try fixture("usage", as: HermesUsage.self).totals.totalSessions == 23)
        #expect(try fixture("status", as: HermesStatus.self).version == "0.21.5")
        #expect(try fixture("profiles", as: ProfilesResponse.self).profiles.count == 5)
    }

    @Test func conversationsDecodeRelayDates() throws {
        let conversations = try fixture("conversations", as: ConversationsResponse.self).conversations
        #expect(conversations.first?.isCurrent == true)
        let allDated = conversations.allSatisfy { $0.lastMessageAt != nil }
        #expect(allDated)
    }

    @Test func liveTransportMapsRelayErrors() {
        #expect(LiveWorkspaceTransport.workspaceError(status: 409, message: "Hermes host is offline.") == .hostOffline)
        #expect(LiveWorkspaceTransport.workspaceError(status: 403, message: "forbidden: nope") == .forbidden("forbidden: nope"))
        #expect(LiveWorkspaceTransport.workspaceError(status: 404, message: "task t_9 not found") == .notFound("task t_9 not found"))
        #expect(LiveWorkspaceTransport.workspaceError(status: 502, message: "boom") == .server("boom"))
    }
}

struct CronSchedulePresetTests {
    @Test func presetsCompileToCron() {
        #expect(CronSchedulePreset.everyMorning(hour: 8, minute: 0).expression == "0 8 * * *")
        #expect(CronSchedulePreset.hourly.expression == "0 * * * *")
        #expect(CronSchedulePreset.weekdays(hour: 9, minute: 30).expression == "30 9 * * 1-5")
        #expect(CronSchedulePreset.weekly(weekday: 1, hour: 18, minute: 0).expression == "0 18 * * 1")
        #expect(CronSchedulePreset.custom(" */15 * * * * ").expression == "*/15 * * * *")
    }

    @Test func commonExpressionsHaveReadableText() {
        #expect(CronSchedulePreset.describe(expression: "0 8 * * *") == "Every day at 08:00")
        #expect(CronSchedulePreset.describe(expression: "30 9 * * 1-5") == "Weekdays at 09:30")
        #expect(CronSchedulePreset.describe(expression: "0 18 * * 0") == "Sundays at 18:00")
        #expect(CronSchedulePreset.describe(expression: "0 * * * *") == "Every hour")
        #expect(CronSchedulePreset.describe(expression: "*/15 * * * *") == nil)
    }
}

@MainActor
struct MockWorkspaceTransportTests {
    @Test func createdTaskAppearsOnBoard() async throws {
        let transport = MockWorkspaceTransport()
        let api = HermesWorkspaceAPI(transport: transport)

        let task = try await api.createTask(KanbanTaskDraft(title: "Find a dentist", body: "Near me", assignee: "researcher"))
        let board = try await api.board()

        let isOnBoard = board.allTasks.contains { $0.id == task.id && $0.status == .ready }
        #expect(isOnBoard)
    }

    @Test func offlineModeThrowsHostOffline() async {
        let api = HermesWorkspaceAPI(transport: MockWorkspaceTransport(mode: .offline))
        await #expect(throws: WorkspaceError.hostOffline) { try await api.board() }
    }

    @Test func soulRoundTripsThroughLocalDecodeShape() async throws {
        let api = HermesWorkspaceAPI(transport: MockWorkspaceTransport())
        try await api.updateSoul(profile: "researcher", content: "Be thorough.")
        #expect(try await api.soul(profile: "researcher") == "Be thorough.")
    }
}
