import SwiftUI

struct TeamScreen: View {
    @Environment(TeamStore.self) private var store
    @Environment(TabRouter.self) private var router
    @State private var openedRole: HermesProfile?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Design.Spacing.lg) {
                if store.isOffline {
                    OfflineBanner { Task { await store.refresh() } }
                        .padding(.horizontal, Design.Spacing.md)
                }

                if !store.roles.isEmpty {
                    RoleStripView(
                        roles: store.roles,
                        selectedRole: store.selectedRole,
                        activity: store.activity(for:),
                        onSelect: { store.selectedRole = $0 },
                        onOpenRole: { openedRole = $0 }
                    )
                }

                content
            }
            .padding(.top, Design.Spacing.xs)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .canvasBackground()
        .navigationTitle("Team")
        .navigationDestination(for: TaskRoute.self) { route in
            TaskDetailScreen(taskID: route.id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.presentSheet(.newTask(prefill: nil))
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New task")
                .accessibilityIdentifier("team.newTask")
            }
        }
        .refreshable { await store.refresh() }
        .onAppear { store.startLivePolling() }
        .onDisappear { store.stopLivePolling() }
        .sheet(item: $openedRole) { profile in
            RoleSheet(profile: profile)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.loadState {
        case .idle, .loading:
            ProgressView()
                .tint(Design.Brand.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, Design.Spacing.xxl)
        case .failed(let message):
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Couldn't load the board",
                message: message,
                actionTitle: "Try again"
            ) {
                Task { await store.refresh() }
            }
        case .loaded where store.sections.isEmpty:
            if let role = store.selectedRole {
                EmptyStateView(
                    systemImage: RoleStyle.forProfile(role).symbol,
                    title: "Nothing for \(RoleStyle.forProfile(role).displayName)",
                    message: "No tasks are assigned to this role right now.",
                    actionTitle: "Show everyone"
                ) {
                    store.selectedRole = nil
                }
            } else {
                EmptyStateView(
                    systemImage: "person.3.sequence",
                    title: "Your team is ready",
                    message: "Give a task to the researcher, operator, coder or reviewer. They work in the background and report back here.",
                    actionTitle: "Give the team a task"
                ) {
                    router.presentSheet(.newTask(prefill: nil))
                }
            }
        case .loaded:
            ForEach(store.sections) { section in
                VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                    SectionHeader(
                        title: section.title,
                        count: section.tasks.count,
                        tint: section.kind == .needsYou ? Design.Colors.warning : Design.Colors.textSecondary
                    )
                    ForEach(section.tasks) { task in
                        NavigationLink(value: TaskRoute(id: task.id)) {
                            TaskCardView(task: task)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("team.task.\(task.id)")
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
            }
        }
    }
}
