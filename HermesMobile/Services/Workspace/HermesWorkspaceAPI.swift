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

    func deleteTask(id: String) async throws {
        try await transport.perform(.delete, "\(Self.kanban)/tasks/\(id)")
    }

    func attachment(id: Int) async throws -> HermesFilePayload {
        try await transport.get("\(Self.kanban)/attachments/\(id)")
    }

    func soul(profile: String) async throws -> String {
        struct Soul: Decodable { let content: String? }
        let response: Soul = try await transport.get("hermes/api/profiles/\(profile)/soul")
        return response.content ?? ""
    }

    func updateSoul(profile: String, content: String) async throws {
        struct Soul: Encodable { let content: String }
        try await transport.perform(.put, "hermes/api/profiles/\(profile)/soul", body: Soul(content: content))
    }

    func updateDescription(profile: String, _ description: String) async throws {
        struct Description: Encodable { let description: String }
        try await transport.perform(.put, "hermes/api/profiles/\(profile)/description", body: Description(description: description))
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

    func pause(jobID: String) async throws {
        try await transport.perform(.post, "\(Self.cron)/jobs/\(jobID)/pause")
    }

    func resume(jobID: String) async throws {
        try await transport.perform(.post, "\(Self.cron)/jobs/\(jobID)/resume")
    }

    func trigger(jobID: String) async throws {
        try await transport.perform(.post, "\(Self.cron)/jobs/\(jobID)/trigger")
    }

    func deleteJob(id: String) async throws {
        try await transport.perform(.delete, "\(Self.cron)/jobs/\(id)")
    }

    func runs(jobID: String) async throws -> [CronRun] {
        let response: CronRunsResponse = try await transport.get("\(Self.cron)/jobs/\(jobID)/runs")
        return response.runs
    }

    /// A cron run is a Hermes session; its output is the final assistant reply.
    func runOutput(runID: String) async throws -> String? {
        let response: SessionMessagesResponse = try await transport.get("hermes/api/sessions/\(runID)/messages")
        return response.finalReply
    }

    // MARK: Library

    func memory() async throws -> HermesMemory {
        try await transport.get("hermes/memory")
    }

    @discardableResult
    func saveMemory(_ kind: HermesMemoryKind, content: String) async throws -> HermesMemoryDocument {
        try await transport.send(.put, "hermes/memory/\(kind.rawValue)", query: [:], body: MemoryWrite(content: content))
    }

    func skills() async throws -> [HermesSkill] {
        try await transport.get("hermes/api/skills")
    }

    func skillContent(name: String) async throws -> String {
        let response: SkillContent = try await transport.get("hermes/api/skills/content", query: ["name": name])
        return response.content
    }

    func setSkill(name: String, enabled: Bool) async throws {
        try await transport.perform(.put, "hermes/api/skills/toggle", body: SkillToggle(name: name, enabled: enabled))
    }

    // MARK: Status

    func status() async throws -> HermesStatus {
        try await transport.get("hermes/api/status")
    }

    func modelInfo() async throws -> HermesModelInfo {
        try await transport.get("hermes/api/model/info")
    }

    func usage(days: Int) async throws -> HermesUsage {
        try await transport.get("hermes/api/analytics/usage", query: ["days": String(days)])
    }

    // MARK: Conversations

    func conversations() async throws -> [ConversationSummary] {
        let response: ConversationsResponse = try await transport.get("conversations")
        return response.conversations
    }

    func newConversation() async throws -> ConversationSummary {
        let response: ConversationResponse = try await transport.send(.post, "conversations", query: [:], body: nil)
        return response.conversation
    }

    func activateConversation(id: String) async throws {
        try await transport.perform(.post, "conversations/\(id)/activate")
    }

    func renameConversation(id: String, title: String) async throws {
        try await transport.perform(.patch, "conversations/\(id)", body: ConversationRename(title: title))
    }

    func archiveConversation(id: String) async throws {
        try await transport.perform(.delete, "conversations/\(id)")
    }

    private static func profileQuery(_ profile: String?) -> [String: String] {
        guard let profile, !profile.isEmpty, profile != RoleStyle.defaultProfileName else { return [:] }
        return ["profile": profile]
    }
}
