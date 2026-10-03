import Foundation

/// The user's Hermes agents (profiles) and which one the app is talking to.
@MainActor
@Observable
final class AgentStore {
    private static let selectionKey = "hermes.selectedAgent"

    private(set) var profiles: [HermesProfile] = []
    private(set) var selected: String
    var onSelectionChanged: (@MainActor (String) async -> Void)?

    private let api: HermesWorkspaceAPI
    private let defaults: UserDefaults

    init(api: HermesWorkspaceAPI, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        selected = defaults.string(forKey: Self.selectionKey) ?? RoleStyle.defaultProfileName
    }

    var ordered: [HermesProfile] {
        let rank = Dictionary(uniqueKeysWithValues: RoleStyle.preferredOrder.enumerated().map { ($1, $0) })
        return profiles.sorted { lhs, rhs in
            switch (rank[lhs.name], rank[rhs.name]) {
            case let (l?, r?): l < r
            case (_?, nil): true
            case (nil, _?): false
            default: lhs.name < rhs.name
            }
        }
    }

    var selectedStyle: RoleStyle { RoleStyle.forProfile(selected) }

    func refresh() async {
        guard let loaded = try? await api.profiles(), !loaded.isEmpty else { return }
        profiles = loaded
        if !loaded.contains(where: { $0.name == selected }) {
            select(RoleStyle.defaultProfileName)
        }
    }

    func select(_ name: String) {
        guard name != selected else { return }
        selected = name
        defaults.set(name, forKey: Self.selectionKey)
        let callback = onSelectionChanged
        Task { await callback?(name) }
    }

    #if DEBUG
    func setProfilesForTesting(_ names: [String]) {
        profiles = names.map { HermesProfile(name: $0, isDefault: $0 == RoleStyle.defaultProfileName, model: nil, provider: nil, description: nil) }
    }
    #endif
}
