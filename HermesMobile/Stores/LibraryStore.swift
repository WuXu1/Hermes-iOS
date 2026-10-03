import Foundation

/// Hermes's memory files and installed skills.
@MainActor
@Observable
final class LibraryStore {
    struct SkillGroup: Identifiable, Equatable {
        let title: String
        let skills: [HermesSkill]
        var id: String { title }
    }

    private(set) var memory: HermesMemory = .empty
    private(set) var skills: [HermesSkill] = []
    private(set) var hasLoaded = false
    private(set) var isOffline = false
    private(set) var errorMessage: String?
    var skillQuery = ""
    /// The agent whose memory and skills are shown.
    var profile: String = RoleStyle.defaultProfileName {
        didSet {
            guard profile != oldValue else { return }
            memory = .empty
            skills = []
            hasLoaded = false
            errorMessage = nil
        }
    }

    private let api: HermesWorkspaceAPI

    init(api: HermesWorkspaceAPI) {
        self.api = api
    }

    var skillsByCategory: [SkillGroup] {
        let needle = skillQuery.trimmingCharacters(in: .whitespaces)
        let matches = skills.filter { skill in
            needle.isEmpty
                || skill.name.localizedCaseInsensitiveContains(needle)
                || (skill.description ?? "").localizedCaseInsensitiveContains(needle)
        }
        return Dictionary(grouping: matches, by: \.categoryTitle)
            .map { SkillGroup(title: $0.key, skills: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.title < $1.title }
    }

    var enabledSkillCount: Int { skills.filter(\.enabled).count }

    func refresh() async {
        let requested = profile
        do {
            async let memory = api.memory(profile: requested)
            async let skills = api.skills(profile: requested)
            let (loadedMemory, loadedSkills) = try await (memory, skills)
            guard profile == requested else { return }
            self.memory = loadedMemory
            self.skills = loadedSkills
            isOffline = false
            errorMessage = nil
        } catch WorkspaceError.hostOffline {
            guard profile == requested else { return }
            isOffline = true
        } catch {
            guard profile == requested else { return }
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
    }

    func reset() {
        profile = RoleStyle.defaultProfileName
        memory = .empty
        skills = []
        hasLoaded = false
        isOffline = false
        errorMessage = nil
        skillQuery = ""
    }

    func save(_ kind: HermesMemoryKind, content: String) async throws {
        let target = profile
        let document = try await api.saveMemory(kind, content: content, profile: target)
        if profile == target { memory[kind] = document }
    }

    /// Optimistic toggle; reverts and reports if the host refuses.
    @discardableResult
    func setSkill(_ skill: HermesSkill, enabled: Bool) async -> Bool {
        guard !(skill.isLocked && !enabled) else { return false }
        guard let index = skills.firstIndex(where: { $0.name == skill.name }) else { return false }
        skills[index].enabled = enabled
        do {
            try await api.setSkill(name: skill.name, enabled: enabled, profile: profile)
            return true
        } catch {
            if let revert = skills.firstIndex(where: { $0.name == skill.name }) {
                skills[revert].enabled = !enabled
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func content(of skill: HermesSkill) async throws -> String {
        try await api.skillContent(name: skill.name, profile: profile)
    }

    #if DEBUG
    func setSkillsForTesting(_ skills: [HermesSkill]) { self.skills = skills }
    #endif
}
