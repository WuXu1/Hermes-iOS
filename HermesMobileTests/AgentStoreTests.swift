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
}
