import SwiftUI

struct MainTabView: View {
    @Environment(TabRouter.self) private var router
    @Environment(TalkStore.self) private var talkStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(TeamStore.self) private var teamStore
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
        .fullScreenCover(isPresented: $router.isVoiceOverlayPresented) {
            VoiceOverlayScreen()
        }
        .task {
            // Keep the Team badge fresh from anywhere in the app.
            await teamStore.refresh()
        }
        .onChange(of: talkStore.lastCompletedSession != nil) { _, hasSession in
            if hasSession, let session = talkStore.lastCompletedSession {
                Task {
                    await chatStore.injectVoiceTranscript(
                        voiceSessionId: session.voiceSessionId,
                        duration: session.duration
                    )
                    talkStore.clearLastCompletedSession()
                }
            }
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
        case .capture:
            CaptureScreen()
        case .connectHost:
            ConnectHermesHostScreen()
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
