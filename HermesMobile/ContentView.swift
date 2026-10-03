import SwiftUI

struct MainTabView: View {
    @Environment(TabRouter.self) private var router
    @Environment(TeamStore.self) private var teamStore
    @Environment(AgentStore.self) private var agentStore
    @Environment(ToastCenter.self) private var toastCenter

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab(AppTab.chat.title, systemImage: AppTab.chat.icon, value: AppTab.chat) {
                tabStack(.chat) { ChatScreen() }
            }
            Tab(AppTab.team.title, systemImage: AppTab.team.icon, value: AppTab.team) {
                tabStack(.team) { TeamScreen() }
            }
            .badge(teamStore.needsYouCount)
            Tab(AppTab.automations.title, systemImage: AppTab.automations.icon, value: AppTab.automations) {
                tabStack(.automations) { AutomationsScreen() }
            }
            Tab(AppTab.library.title, systemImage: AppTab.library.icon, value: AppTab.library) {
                tabStack(.library) { LibraryScreen() }
            }
        }
        .tint(Design.Brand.accent)
        .tabBarMinimizeBehavior(.onScrollDown)
        .toastOverlay(toastCenter)
        .sheet(item: $router.activeSheet) { destination in
            sheetDestination(destination)
        }
        .task {
            // Keep the Team badge fresh from anywhere in the app.
            await teamStore.refresh()
            await agentStore.refresh()
        }
    }

    private func tabStack<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: router.pathBinding(for: tab)) {
            content()
                .navigationDestination(for: Route.self) { route in
                    routeDestination(route)
                }
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: Route) -> some View {
        switch route {
        case .permissions:
            PermissionsScreen()
        }
    }

    @ViewBuilder
    private func sheetDestination(_ destination: SheetDestination) -> some View {
        switch destination {
        case .settings:
            NavigationStack {
                SettingsScreen()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        case .history:
            HistorySheet()
        case .newTask(let prefill):
            NewTaskSheet(prefill: prefill)
        case .newAutomation(let blueprintKey):
            NewAutomationSheet(initialBlueprintKey: blueprintKey)
        }
    }
}
