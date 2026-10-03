import Foundation

/// Typed calls for the workspace screens. Hermes dashboard routes go through the
/// relay's allowlisted proxy (`hermes/api/...`); memory and conversations have
/// dedicated relay endpoints.
@MainActor
struct HermesWorkspaceAPI {
    let transport: any WorkspaceTransport

    private static let kanban = "hermes/api/plugins/kanban"
    private static let cron = "hermes/api/cron"

    // MARK: Team

    func board() async throws -> KanbanBoard {
        try await transport.get("\(Self.kanban)/board")
    }

    func profiles() async throws -> [HermesProfile] {
        let response: ProfilesResponse = try await transport.get("hermes/api/profiles")
        return response.profiles
    }

    func task(id: String) async throws -> KanbanTaskDetail {
        try await transport.get("\(Self.kanban)/tasks/\(id)")
    }

    func taskLog(id: String) async throws -> KanbanTaskLog {
        try await transport.get("\(Self.kanban)/tasks/\(id)/log")
    }

    @discardableResult
    func createTask(_ draft: KanbanTaskDraft) async throws -> KanbanTask {
        let response: TaskResponse = try await transport.send(.post, "\(Self.kanban)/tasks", query: [:], body: draft)
        return response.task
    }

    func updateTask(id: String, _ patch: KanbanTaskPatch) async throws {
        try await transport.perform(.patch, "\(Self.kanban)/tasks/\(id)", body: patch)
    }

    func comment(taskID: String, body: String) async throws {
        struct Comment: Encodable { let body: String; let author = "you" }
        try await transport.perform(.post, "\(Self.kanban)/tasks/\(taskID)/comments", body: Comment(body: body))
    }

    func reassign(taskID: String, to profile: String) async throws {
        struct Reassign: Encodable {
            let profile: String
            let reclaimFirst = true

            enum CodingKeys: String, CodingKey {
                case profile
                case reclaimFirst = "reclaim_first"
            }
        }
        try await transport.perform(.post, "\(Self.kanban)/tasks/\(taskID)/reassign", body: Reassign(profile: profile))
    }

    func attachment(id: Int) async throws -> HermesFilePayload {
        try await transport.get("\(Self.kanban)/attachments/\(id)")
    }

    func soul(profile: String) async throws -> String {
        struct Soul: Decodable { let content: String? }
        let response: Soul = try await transport.get("hermes/api/profiles/\(profile)/soul")
        return response.content ?? ""
    }

    // MARK: Automations

    func jobs() async throws -> [CronJob] {
        try await transport.get("\(Self.cron)/jobs")
    }

    func blueprints() async throws -> [CronBlueprint] {
        let response: CronBlueprintsResponse = try await transport.get("\(Self.cron)/blueprints")
        return response.blueprints
    }

    func createJob(_ draft: CronJobDraft, profile: String?) async throws {
        try await transport.perform(.post, "\(Self.cron)/jobs", query: Self.profileQuery(profile), body: draft)
    }

    func instantiate(blueprint: String, values: [String: String]) async throws {
        try await transport.perform(
            .post,
            "\(Self.cron)/blueprints/instantiate",
            body: BlueprintInstantiation(blueprint: blueprint, values: values)
        )
    }

    func pause(jobID: String, profile: String?) async throws {
        try await transport.perform(.post, "\(Self.cron)/jobs/\(jobID)/pause", query: Self.profileQuery(profile))
    }

    func resume(jobID: String, profile: String?) async throws {
        try await transport.perform(.post, "\(Self.cron)/jobs/\(jobID)/resume", query: Self.profileQuery(profile))
    }

    func trigger(jobID: String, profile: String?) async throws {
        try await transport.perform(.post, "\(Self.cron)/jobs/\(jobID)/trigger", query: Self.profileQuery(profile))
    }

    func runs(jobID: String, profile: String?) async throws -> [CronRun] {
        let response: CronRunsResponse = try await transport.get("\(Self.cron)/jobs/\(jobID)/runs", query: Self.profileQuery(profile))
        return response.runs
    }

    /// A cron run is a Hermes session; its output is the final assistant reply.
    func runOutput(runID: String, profile: String?) async throws -> String? {
        let response: SessionMessagesResponse = try await transport.get("hermes/api/sessions/\(runID)/messages", query: Self.profileQuery(profile))
        return response.finalReply
    }

    // MARK: Library

    func memory(profile: String) async throws -> HermesMemory {
        try await transport.get("hermes/memory", query: ["profile": profile])
    }

    @discardableResult
    func saveMemory(_ kind: HermesMemoryKind, content: String, profile: String) async throws -> HermesMemoryDocument {
        try await transport.send(.put, "hermes/memory/\(kind.rawValue)", query: ["profile": profile], body: MemoryWrite(content: content))
    }

    func skills(profile: String) async throws -> [HermesSkill] {
        try await transport.get("hermes/api/skills", query: ["profile": profile])
    }

    func skillContent(name: String, profile: String) async throws -> String {
        let response: SkillContent = try await transport.get("hermes/api/skills/content", query: ["name": name, "profile": profile])
        return response.content
    }

    func setSkill(name: String, enabled: Bool, profile: String) async throws {
        try await transport.perform(.put, "hermes/api/skills/toggle", query: ["profile": profile], body: SkillToggle(name: name, enabled: enabled))
    }

    // MARK: Status

    func status() async throws -> HermesStatus {
        try await transport.get("hermes/api/status")
    }

    func modelInfo(profile: String?) async throws -> HermesModelInfo {
        try await transport.get("hermes/api/model/info", query: Self.profileQuery(profile))
    }

    func usage(days: Int, profile: String?) async throws -> HermesUsage {
        try await transport.get("hermes/api/analytics/usage", query: ["days": String(days)].merging(Self.profileQuery(profile)) { $1 })
    }

    // MARK: Conversations (Hermes sessions for one agent)

    func sessions(profile: String) async throws -> [HermesSessionSummary] {
        let response: HermesSessionsResponse = try await transport.get(
            "hermes/api/sessions",
            query: ["profile": profile, "order": "recent", "limit": "50", "exclude_sources": "cron,subagent"]
        )
        return response.sessions
    }

    func openSession(profile: String, id: String) async throws {
        try await transport.perform(.post, "conversations/open", body: ConversationOpen(profile: profile, sessionId: id))
    }

    func newConversation(profile: String) async throws {
        try await transport.perform(.post, "conversations", body: ConversationCreate(profile: profile))
    }

    func renameSession(id: String, title: String, profile: String) async throws {
        try await transport.perform(.patch, "hermes/api/sessions/\(id)", query: ["profile": profile], body: SessionPatch(title: title, archived: nil))
    }

    func archiveSession(id: String, profile: String) async throws {
        try await transport.perform(.patch, "hermes/api/sessions/\(id)", query: ["profile": profile], body: SessionPatch(title: nil, archived: true))
    }

    private static func profileQuery(_ profile: String?) -> [String: String] {
        guard let profile, !profile.isEmpty, profile != RoleStyle.defaultProfileName else { return [:] }
        return ["profile": profile]
    }
}
