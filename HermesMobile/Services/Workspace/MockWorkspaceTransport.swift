import Foundation

/// Serves recorded fixtures (`Resources/MockFixtures`) and applies mutations to
/// in-memory state, so mock-mode screens react to actions like a real host.
/// Used for UI tests, previews and simulator screenshots.
@MainActor
final class MockWorkspaceTransport: WorkspaceTransport {
    enum Mode {
        case online
        case offline
    }

    var mode: Mode
    private(set) var requests: [(method: HTTPMethod, path: String)] = []

    private(set) var board: KanbanBoard
    private(set) var jobs: [CronJob]
    private(set) var memory: HermesMemory
    private(set) var skills: [HermesSkill]
    private(set) var conversations: [ConversationSummary]
    private var comments: [String: [KanbanComment]] = [:]
    private var souls: [String: String] = [:]
    private var nextID = 1

    private let bundle: Bundle

    init(mode: Mode = .online, bundle: Bundle = .main) {
        self.mode = mode
        self.bundle = bundle
        board = Self.load("board", bundle: bundle) ?? .empty
        jobs = Self.load("cron_jobs", bundle: bundle) ?? []
        memory = Self.load("memory", bundle: bundle) ?? .empty
        skills = Self.load("skills", bundle: bundle) ?? []
        conversations = (Self.load("conversations", bundle: bundle) as ConversationsResponse?)?.conversations ?? []
    }

    func send<Response: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String],
        body: (any Encodable)?
    ) async throws -> Response {
        requests.append((method, path))
        guard mode == .online else { throw WorkspaceError.hostOffline }

        let value = try handle(method, path.split(separator: "/").map(String.init), query: query, body: body)
        if let typed = value as? Response {
            return typed
        }
        if value is IgnoredResponse || Response.self == IgnoredResponse.self {
            return try JSONDecoder().decode(Response.self, from: Data("{}".utf8))
        }
        // Callers may decode into their own shape (e.g. a local struct); round-trip through JSON.
        if let encodable = value as? any Encodable {
            return try JSONDecoder().decode(Response.self, from: JSONEncoder().encode(encodable))
        }
        throw WorkspaceError.server("Mock returned \(type(of: value)) for \(method.rawValue) \(path), expected \(Response.self)")
    }

    // MARK: Routing

    /// Captured `*` segments when `method` and the `/`-separated `pattern` match.
    private func match(_ parts: [String], _ method: HTTPMethod, _ expected: HTTPMethod, _ pattern: String) -> [String]? {
        guard method == expected else { return nil }
        let segments = pattern.split(separator: "/").map(String.init)
        guard segments.count == parts.count else { return nil }
        var captures: [String] = []
        for (segment, part) in zip(segments, parts) {
            if segment == "*" {
                captures.append(part)
            } else if segment != part {
                return nil
            }
        }
        return captures
    }

    private func handle(_ method: HTTPMethod, _ parts: [String], query: [String: String], body: (any Encodable)?) throws -> Any {
        func route(_ expected: HTTPMethod, _ pattern: String) -> [String]? {
            match(parts, method, expected, pattern)
        }
        let kanban = "hermes/api/plugins/kanban"
        let cron = "hermes/api/cron"

        // Team
        if route(.get, "\(kanban)/board") != nil { return board }
        if route(.get, "hermes/api/profiles") != nil { return try fixture("profiles") as ProfilesResponse }
        if let id = route(.get, "\(kanban)/tasks/*")?.first { return try taskDetail(id: id) }
        if route(.get, "\(kanban)/tasks/*/log") != nil { return try fixture("task_log") as KanbanTaskLog }
        if route(.post, "\(kanban)/tasks") != nil {
            return TaskResponse(task: insertTask(try decode(body, as: KanbanTaskDraft.self)))
        }
        if let id = route(.patch, "\(kanban)/tasks/*")?.first {
            let patch = try decode(body, as: PatchBody.self)
            try updateTask(id) { task in
                if let status = patch.status { task.status = KanbanStatus(apiValue: status) }
                if task.status == .done { task.completedAtUnix = Date().timeIntervalSince1970 }
                if task.status == .ready { task.lastFailureError = nil }
            }
            return IgnoredResponse()
        }
        if let id = route(.post, "\(kanban)/tasks/*/comments")?.first {
            let comment = try decode(body, as: CommentBody.self)
            comments[id, default: []].append(
                KanbanComment(id: makeID(), author: comment.author, body: comment.body, createdAtUnix: Date().timeIntervalSince1970)
            )
            return IgnoredResponse()
        }
        if let id = route(.post, "\(kanban)/tasks/*/reassign")?.first {
            let reassign = try decode(body, as: ReassignBody.self)
            try updateTask(id) { $0.assignee = reassign.profile }
            return IgnoredResponse()
        }
        if let id = route(.delete, "\(kanban)/tasks/*")?.first {
            for index in board.columns.indices {
                board.columns[index].tasks.removeAll { $0.id == id }
            }
            return IgnoredResponse()
        }
        if route(.get, "\(kanban)/attachments/*") != nil {
            let text = "# Sample output\n\n| date | amount | note |\n|---|---|---|\n| 2026-09-01 | -12.40 | Coffee |\n| 2026-09-02 | -54.00 | Groceries |\n"
            return HermesFilePayload(contentType: "text/markdown", base64: Data(text.utf8).base64EncodedString())
        }
        if let name = route(.get, "hermes/api/profiles/*/soul")?.first {
            return SoulBody(content: souls[name] ?? "You are the \(name) on the user's Hermes team.")
        }
        if let name = route(.put, "hermes/api/profiles/*/soul")?.first {
            souls[name] = try decode(body, as: SoulBody.self).content
            return IgnoredResponse()
        }
        if route(.put, "hermes/api/profiles/*/description") != nil { return IgnoredResponse() }

        // Automations
        if route(.get, "\(cron)/jobs") != nil { return jobs }
        if route(.get, "\(cron)/blueprints") != nil { return try fixture("cron_blueprints") as CronBlueprintsResponse }
        if route(.post, "\(cron)/jobs") != nil {
            let draft = try decode(body, as: CronJobDraftBody.self)
            jobs.append(makeJob(name: draft.name, prompt: draft.prompt, schedule: draft.schedule, profile: query["profile"]))
            return IgnoredResponse()
        }
        if route(.post, "\(cron)/blueprints/instantiate") != nil {
            let request = try decode(body, as: BlueprintBody.self)
            let name = request.blueprint.replacingOccurrences(of: "-", with: " ").capitalized
            jobs.append(makeJob(name: name, prompt: "Blueprint: \(request.blueprint)", schedule: "0 8 * * *", profile: nil))
            return IgnoredResponse()
        }
        if let captures = route(.post, "\(cron)/jobs/*/*"), ["pause", "resume", "trigger"].contains(captures[1]) {
            let (id, action) = (captures[0], captures[1])
            guard let index = jobs.firstIndex(where: { $0.id == id }) else { throw WorkspaceError.notFound("job \(id) not found") }
            if action != "trigger" {
                jobs[index].enabled = action == "resume"
                jobs[index].state = action == "resume" ? "scheduled" : "paused"
            }
            return IgnoredResponse()
        }
        if let id = route(.delete, "\(cron)/jobs/*")?.first {
            jobs.removeAll { $0.id == id }
            return IgnoredResponse()
        }
        if route(.get, "\(cron)/jobs/*/runs") != nil { return try fixture("cron_runs") as CronRunsResponse }
        if route(.get, "hermes/api/sessions/*/messages") != nil { return try fixture("session_messages") as SessionMessagesResponse }

        // Library
        if route(.get, "hermes/memory") != nil { return memory }
        if let rawKind = route(.put, "hermes/memory/*")?.first {
            guard let kind = HermesMemoryKind(rawValue: rawKind) else { throw WorkspaceError.server("invalid memory kind") }
            let document = HermesMemoryDocument(
                content: try decode(body, as: MemoryBody.self).content,
                updatedAtUnix: Date().timeIntervalSince1970
            )
            memory[kind] = document
            return document
        }
        if route(.get, "hermes/api/skills") != nil { return skills }
        if route(.get, "hermes/api/skills/content") != nil { return try fixture("skill_content") as SkillContent }
        if route(.put, "hermes/api/skills/toggle") != nil {
            let toggle = try decode(body, as: ToggleBody.self)
            if let index = skills.firstIndex(where: { $0.name == toggle.name }) { skills[index].enabled = toggle.enabled }
            return IgnoredResponse()
        }

        // Status
        if route(.get, "hermes/api/status") != nil { return try fixture("status") as HermesStatus }
        if route(.get, "hermes/api/model/info") != nil { return try fixture("model_info") as HermesModelInfo }
        if route(.get, "hermes/api/analytics/usage") != nil { return try fixture("usage") as HermesUsage }

        // Conversations
        if route(.get, "conversations") != nil { return ConversationsResponse(conversations: conversations) }
        if route(.post, "conversations") != nil {
            let summary = ConversationSummary(id: UUID().uuidString, title: "New chat", preview: "", lastMessageAt: Date(), isCurrent: true)
            conversations = [summary] + conversations.map { var copy = $0; copy.isCurrent = false; return copy }
            return ConversationResponse(conversation: summary)
        }
        if let id = route(.post, "conversations/*/activate")?.first {
            conversations = conversations.map { var copy = $0; copy.isCurrent = copy.id == id; return copy }
            return IgnoredResponse()
        }
        if let id = route(.patch, "conversations/*")?.first {
            let rename = try decode(body, as: RenameBody.self)
            if let index = conversations.firstIndex(where: { $0.id == id }) { conversations[index].title = rename.title }
            return IgnoredResponse()
        }
        if let id = route(.delete, "conversations/*")?.first {
            conversations.removeAll { $0.id == id }
            return IgnoredResponse()
        }

        throw WorkspaceError.notFound("No mock route for \(method.rawValue) \(parts.joined(separator: "/"))")
    }

    // MARK: State helpers

    private func taskDetail(id: String) throws -> KanbanTaskDetail {
        guard let task = board.allTasks.first(where: { $0.id == id }) else {
            throw WorkspaceError.notFound("task \(id) not found")
        }
        var detail: KanbanTaskDetail = (try? fixture("task_detail")) ?? KanbanTaskDetail(task: task)
        if detail.task.id != id {
            detail = KanbanTaskDetail(task: task, events: detail.events.prefix(1).map { event in
                var copy = event
                copy.createdAtUnix = task.createdAtUnix
                return copy
            })
        } else {
            detail.task = task
        }
        detail.comments += comments[id] ?? []
        return detail
    }

    private func insertTask(_ draft: KanbanTaskDraft) -> KanbanTask {
        let status: KanbanStatus = draft.parents.isEmpty ? .ready : .todo
        let task = KanbanTask(
            id: "t_mock\(makeID())",
            title: draft.title,
            body: draft.body,
            assignee: draft.assignee,
            status: status,
            priority: 0,
            createdBy: "you",
            createdAtUnix: Date().timeIntervalSince1970
        )
        if let index = board.columns.firstIndex(where: { $0.name == status.rawValue }) {
            board.columns[index].tasks.insert(task, at: 0)
        } else {
            board.columns.append(KanbanColumn(name: status.rawValue, tasks: [task]))
        }
        return task
    }

    private func updateTask(_ id: String, _ change: (inout KanbanTask) -> Void) throws {
        guard var task = board.allTasks.first(where: { $0.id == id }) else {
            throw WorkspaceError.notFound("task \(id) not found")
        }
        change(&task)
        for index in board.columns.indices {
            board.columns[index].tasks.removeAll { $0.id == id }
        }
        if let index = board.columns.firstIndex(where: { $0.name == task.status.rawValue }) {
            board.columns[index].tasks.insert(task, at: 0)
        } else {
            board.columns.append(KanbanColumn(name: task.status.rawValue, tasks: [task]))
        }
    }

    private func makeJob(name: String, prompt: String, schedule: String, profile: String?) -> CronJob {
        CronJob(
            id: "mock\(makeID())",
            name: name,
            prompt: prompt,
            schedule: CronSchedule(kind: "cron", expr: schedule, display: schedule),
            scheduleDisplay: schedule,
            enabled: true,
            state: "scheduled",
            nextRunAtRaw: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)),
            deliver: "local",
            profile: profile ?? RoleStyle.defaultProfileName
        )
    }

    private func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private func fixture<T: Decodable>(_ name: String) throws -> T {
        guard let value: T = Self.load(name, bundle: bundle) else {
            throw WorkspaceError.server("Missing fixture \(name).json")
        }
        return value
    }

    static func load<T: Decodable>(_ name: String, bundle: Bundle) -> T? {
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? RelayCoders.makeDecoder().decode(T.self, from: data)
    }

    private func decode<T: Decodable>(_ body: (any Encodable)?, as type: T.Type) throws -> T {
        guard let body else { throw WorkspaceError.server("Missing request body") }
        let data = try JSONEncoder().encode(body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // Request bodies as the mock reads them back.
    private struct PatchBody: Decodable { var status: String? }
    private struct CommentBody: Decodable { var body: String; var author: String? }
    private struct ReassignBody: Decodable { var profile: String? }
    private struct SoulBody: Codable { var content: String }
    private struct CronJobDraftBody: Decodable { var name: String; var prompt: String; var schedule: String }
    private struct BlueprintBody: Decodable { var blueprint: String }
    private struct MemoryBody: Decodable { var content: String }
    private struct ToggleBody: Decodable { var name: String; var enabled: Bool }
    private struct RenameBody: Decodable { var title: String }
}
