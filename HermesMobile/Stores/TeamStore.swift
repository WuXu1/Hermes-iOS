import Foundation

/// The kanban team: the board, the roles (profiles) and task actions.
@MainActor
@Observable
final class TeamStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    struct Section: Identifiable, Equatable {
        enum Kind: String {
            case needsYou, working, upNext, review, done
        }

        let kind: Kind
        let tasks: [KanbanTask]

        var id: String { kind.rawValue }

        var title: String {
            switch kind {
            case .needsYou: "Needs you"
            case .working: "Working"
            case .upNext: "Up next"
            case .review: "In review"
            case .done: "Done"
            }
        }
    }

    /// Display order for known roles; others follow alphabetically.
    private static let roleOrder = [RoleStyle.defaultProfileName, "researcher", "operator", "coder", "reviewer"]
    private static let doneLimit = 20
    private static let pollInterval: Duration = .seconds(10)

    private(set) var board: KanbanBoard = .empty
    private(set) var profiles: [HermesProfile] = []
    private(set) var loadState: LoadState = .idle
    private(set) var isOffline = false
    var selectedRole: String?

    private let api: HermesWorkspaceAPI
    private var pollingTask: Task<Void, Never>?

    init(api: HermesWorkspaceAPI) {
        self.api = api
    }

    // MARK: Derived state

    var sections: [Section] {
        let tasks = board.allTasks.filter { selectedRole == nil || $0.assignee == selectedRole }
        let byPriorityThenAge: (KanbanTask, KanbanTask) -> Bool = { lhs, rhs in
            if (lhs.priority ?? 0) != (rhs.priority ?? 0) { return (lhs.priority ?? 0) > (rhs.priority ?? 0) }
            return (lhs.createdAtUnix ?? 0) < (rhs.createdAtUnix ?? 0)
        }
        let candidates: [Section] = [
            Section(kind: .needsYou, tasks: tasks.filter(Self.needsUser).sorted(by: byPriorityThenAge)),
            Section(kind: .working, tasks: tasks.filter { $0.status == .running }.sorted(by: byPriorityThenAge)),
            Section(
                kind: .upNext,
                tasks: tasks.filter { [.triage, .todo, .ready, .scheduled].contains($0.status) }.sorted(by: byPriorityThenAge)
            ),
            Section(kind: .review, tasks: tasks.filter { $0.status == .review && !Self.needsUser($0) }.sorted(by: byPriorityThenAge)),
            Section(
                kind: .done,
                tasks: Array(
                    tasks.filter { $0.status == .done }
                        .sorted { ($0.completedAtUnix ?? 0) > ($1.completedAtUnix ?? 0) }
                        .prefix(Self.doneLimit)
                )
            ),
        ]
        return candidates.filter { !$0.tasks.isEmpty }
    }

    var needsYouCount: Int { board.allTasks.filter(Self.needsUser).count }
    var workingCount: Int { board.allTasks.filter { $0.status == .running }.count }

    var roles: [HermesProfile] {
        profiles.sorted { lhs, rhs in
            let left = Self.roleOrder.firstIndex(of: lhs.name) ?? Int.max
            let right = Self.roleOrder.firstIndex(of: rhs.name) ?? Int.max
            return left == right ? lhs.name < rhs.name : left < right
        }
    }

    /// Roles that can take tasks (everyone except the chief of staff).
    var assignableRoles: [HermesProfile] { roles.filter { !$0.isDefault } }

    func activity(for profile: String) -> (isWorking: Bool, openCount: Int) {
        let open = board.allTasks.filter { $0.assignee == profile && $0.status.isOpen }
        return (open.contains { $0.status == .running }, open.count)
    }

    func task(id: String) -> KanbanTask? {
        board.allTasks.first { $0.id == id }
    }

    /// Blocked work, and review items no reviewer will pick up, wait on the user.
    private static func needsUser(_ task: KanbanTask) -> Bool {
        task.status == .blocked || (task.status == .review && (task.assignee ?? "").isEmpty)
    }

    // MARK: Loading

    func refresh() async {
        if loadState == .idle { loadState = .loading }
        do {
            async let board = api.board()
            async let profiles = api.profiles()
            self.board = try await board
            self.profiles = try await profiles
            isOffline = false
            loadState = .loaded
        } catch WorkspaceError.hostOffline {
            isOffline = true
            if loadState == .loading { loadState = .loaded }
        } catch {
            loadState = board.allTasks.isEmpty ? .failed(error.localizedDescription) : .loaded
        }
    }

    func startLivePolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stopLivePolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Clears everything (after unpairing).
    func reset() {
        stopLivePolling()
        board = .empty
        profiles = []
        loadState = .idle
        isOffline = false
        selectedRole = nil
    }

    // MARK: Actions

    /// Creates a task; with `reviewAfter`, also a reviewer task that waits on it.
    @discardableResult
    func create(_ draft: KanbanTaskDraft, reviewAfter: Bool) async throws -> KanbanTask {
        let task = try await api.createTask(draft)
        if reviewAfter {
            try await api.createTask(
                KanbanTaskDraft(
                    title: "Review: \(draft.title)",
                    body: "Check the work from task \(task.id) (\(draft.title)) before it's used. Verify it instead of trusting the summary.",
                    assignee: "reviewer",
                    parents: [task.id]
                )
            )
        }
        await refresh()
        return task
    }

    /// Posts a comment; a blocked task goes back to its queue so the worker retries.
    func reply(to task: KanbanTask, with text: String) async throws {
        try await api.comment(taskID: task.id, body: text)
        if task.status == .blocked {
            try await api.updateTask(id: task.id, KanbanTaskPatch(status: .ready))
        }
        await refresh()
    }

    func approve(_ task: KanbanTask) async throws {
        try await api.updateTask(id: task.id, KanbanTaskPatch(status: .done, summary: task.latestSummary))
        await refresh()
    }

    func requestChanges(_ task: KanbanTask, notes: String) async throws {
        try await api.comment(taskID: task.id, body: notes)
        try await api.updateTask(id: task.id, KanbanTaskPatch(status: .ready))
        await refresh()
    }

    func markDone(_ task: KanbanTask) async throws {
        try await api.updateTask(id: task.id, KanbanTaskPatch(status: .done))
        await refresh()
    }

    func reassign(_ task: KanbanTask, to profile: String) async throws {
        try await api.reassign(taskID: task.id, to: profile)
        await refresh()
    }

    func delete(_ task: KanbanTask) async throws {
        try await api.deleteTask(id: task.id)
        await refresh()
    }

    // MARK: Pass-throughs for detail screens

    func detail(for id: String) async throws -> KanbanTaskDetail { try await api.task(id: id) }
    func log(for id: String) async throws -> KanbanTaskLog { try await api.taskLog(id: id) }
    func attachment(_ attachment: KanbanAttachment) async throws -> HermesFilePayload { try await api.attachment(id: attachment.id) }
    func soul(for profile: String) async throws -> String { try await api.soul(profile: profile) }
    func saveSoul(_ content: String, for profile: String) async throws { try await api.updateSoul(profile: profile, content: content) }

    func saveDescription(_ description: String, for profile: String) async throws {
        try await api.updateDescription(profile: profile, description)
        await refresh()
    }
}
