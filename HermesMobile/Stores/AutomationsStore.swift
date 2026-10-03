import Foundation

/// Scheduled jobs (Hermes cron) and blueprint templates.
@MainActor
@Observable
final class AutomationsStore {
    private(set) var jobs: [CronJob] = []
    private(set) var blueprints: [CronBlueprint] = []
    private(set) var hasLoaded = false
    private(set) var isOffline = false
    private(set) var errorMessage: String?
    var onChanged: (@MainActor () -> Void)?

    private let api: HermesWorkspaceAPI

    init(api: HermesWorkspaceAPI) {
        self.api = api
    }

    func refresh() async {
        do {
            async let jobs = api.jobs()
            async let blueprints = api.blueprints()
            self.jobs = try await jobs
            self.blueprints = try await blueprints
            isOffline = false
            errorMessage = nil
        } catch WorkspaceError.hostOffline {
            isOffline = true
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
        onChanged?()
    }

    func reset() {
        jobs = []
        blueprints = []
        hasLoaded = false
        isOffline = false
        errorMessage = nil
    }

    func create(_ draft: CronJobDraft, profile: String?) async throws {
        try await api.createJob(draft, profile: profile)
        await refresh()
    }

    func instantiate(_ blueprint: CronBlueprint, values: [String: String]) async throws {
        try await api.instantiate(blueprint: blueprint.key, values: values)
        await refresh()
    }

    func togglePause(_ job: CronJob) async throws {
        if job.isPaused {
            try await api.resume(jobID: job.id, profile: job.profile)
        } else {
            try await api.pause(jobID: job.id, profile: job.profile)
        }
        await refresh()
    }

    func runNow(_ job: CronJob) async throws {
        try await api.trigger(jobID: job.id, profile: job.profile)
    }

    func runs(for job: CronJob) async throws -> [CronRun] {
        try await api.runs(jobID: job.id, profile: job.profile)
    }

    func output(for run: CronRun, profile: String?) async throws -> String? {
        try await api.runOutput(runID: run.id, profile: profile)
    }
}
