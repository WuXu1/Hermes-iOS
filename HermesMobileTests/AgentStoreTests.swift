import XCTest
@testable import HermesMobile

@MainActor
final class AgentStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "AgentStoreTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testOrderingPutsCommanderFirstThenKnownAgents() {
        let store = AgentStore(api: HermesWorkspaceAPI(transport: MockWorkspaceTransport(mode: .offline)), defaults: makeDefaults())
        store.setProfilesForTesting(["coach", "zeta", "default", "tutor", "developer", "assistant"])
        XCTAssertEqual(store.ordered.map(\.name), ["default", "developer", "tutor", "assistant", "coach", "zeta"])
    }

    func testSelectionPersistsAndNotifies() async {
        let defaults = makeDefaults()
        let store = AgentStore(api: HermesWorkspaceAPI(transport: MockWorkspaceTransport(mode: .offline)), defaults: defaults)
        var notified: [String] = []
        store.onSelectionChanged = { notified.append($0) }
        store.select("tutor")
        await Task.yield()
        XCTAssertEqual(store.selected, "tutor")
        XCTAssertEqual(defaults.string(forKey: "hermes.selectedAgent"), "tutor")
        XCTAssertEqual(notified, ["tutor"])
        XCTAssertEqual(AgentStore(api: HermesWorkspaceAPI(transport: MockWorkspaceTransport(mode: .offline)), defaults: defaults).selected, "tutor")
    }

    private func labelStore(_ names: [String], displayNames: [String: String?] = [:]) -> AgentStore {
        let store = AgentStore(api: HermesWorkspaceAPI(transport: MockWorkspaceTransport(mode: .offline)), defaults: makeDefaults())
        store.setProfilesForTesting(names, displayNames: displayNames)
        return store
    }

    func testLabelPrefersHermesDisplayName() {
        let store = labelStore(["developer"], displayNames: ["developer": "  Sample  "])
        XCTAssertEqual(store.label(for: "developer"), "Sample")
    }

    func testLabelFallsBackWhenDisplayNameBlank() {
        let store = labelStore(["developer", "tutor"], displayNames: ["developer": "   ", "tutor": ""])
        XCTAssertEqual(store.label(for: "developer"), "Developer")
        XCTAssertEqual(store.label(for: "tutor"), "Tutor")
    }

    func testLabelFallbacks() {
        let store = labelStore(["default", "my-helper"])
        XCTAssertEqual(store.label(for: "default"), "Commander")
        XCTAssertEqual(store.label(for: "my-helper"), RoleStyle.forProfile("my-helper").displayName)
        XCTAssertEqual(store.label(for: "unlisted"), RoleStyle.forProfile("unlisted").displayName)
        XCTAssertEqual(store.label(for: nil), "Unassigned")
        XCTAssertEqual(store.label(for: ""), "Unassigned")
    }

    func testSelectedLabelFollowsSelection() {
        let store = labelStore(["default", "developer"], displayNames: ["developer": "Sample"])
        XCTAssertEqual(store.selectedLabel, "Commander")
        store.select("developer")
        XCTAssertEqual(store.selectedLabel, "Sample")
    }
}
