import SwiftUI

/// Navigation value for an automation's detail screen.
struct JobRoute: Hashable {
    let id: String
}

struct AutomationsScreen: View {
    @Environment(AutomationsStore.self) private var store
    @Environment(TabRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Design.Spacing.lg) {
                if store.isOffline {
                    OfflineBanner { Task { await store.refresh() } }
                }

                if !store.hasLoaded {
                    ProgressView()
                        .tint(Design.Brand.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Design.Spacing.xxl)
                } else if store.jobs.isEmpty {
                    EmptyStateView(
                        systemImage: "clock.arrow.2.circlepath",
                        title: "Put Hermes on a schedule",
                        message: "Automations run on their own: a morning briefing, a price watch, a weekly review. Results land here."
                    )
                    .padding(.top, Design.Spacing.md)
                } else {
                    VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                        SectionHeader(title: "Your automations", count: store.jobs.count)
                        ForEach(store.jobs) { job in
                            NavigationLink(value: JobRoute(id: job.id)) {
                                JobRow(job: job) { togglePause(job) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("automations.job.\(job.id)")
                        }
                    }
                }

                if !store.blueprints.isEmpty {
                    VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                        SectionHeader(title: store.jobs.isEmpty ? "Start from a template" : "Ideas")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Design.Spacing.sm) {
                            ForEach(store.blueprints.prefix(store.jobs.isEmpty ? 8 : 4)) { blueprint in
                                BlueprintCard(blueprint: blueprint) {
                                    router.presentSheet(.newAutomation(blueprintKey: blueprint.key))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.top, Design.Spacing.xs)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .canvasBackground()
        .navigationTitle("Automations")
        .navigationDestination(for: JobRoute.self) { route in
            JobDetailScreen(jobID: route.id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.presentSheet(.newAutomation(blueprintKey: nil))
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New automation")
                .accessibilityIdentifier("automations.new")
            }
        }
        .refreshable { await store.refresh() }
        .task { await store.refresh() }
    }

    private func togglePause(_ job: CronJob) {
        Task {
            do {
                try await store.togglePause(job)
                toasts.show(job.isPaused ? "Resumed" : "Paused", systemImage: job.isPaused ? "play.fill" : "pause.fill")
            } catch {
                toasts.showError(error.localizedDescription)
            }
        }
    }
}

struct JobRow: View {
    let job: CronJob
    let onTogglePause: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            ZStack {
                Circle().fill((job.isPaused ? Design.Colors.textTertiary : Design.Brand.accent).opacity(0.15))
                Image(systemName: job.isPaused ? "pause.fill" : "clock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(job.isPaused ? Design.Colors.textTertiary : Design.Brand.accent)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(job.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(2)
                Text(job.scheduleText)
                    .font(.subheadline)
                    .foregroundStyle(Design.Colors.textSecondary)
                HStack(spacing: Design.Spacing.xs) {
                    if let status = job.lastStatus {
                        StatusPill(
                            label: status == "ok" ? "OK" : "Failed",
                            color: status == "ok" ? Design.Colors.success : Design.Colors.danger,
                            systemImage: status == "ok" ? "checkmark" : "exclamationmark"
                        )
                    }
                    Text(job.isPaused ? "Paused" : "Next \(RelativeTime.future(job.nextRunAt))")
                        .font(.caption)
                        .foregroundStyle(Design.Colors.textTertiary)
                    if let profile = job.profile, profile != RoleStyle.defaultProfileName {
                        RoleAvatar(style: RoleStyle.forProfile(profile), size: .small)
                            .scaleEffect(0.8)
                    }
                }
            }
            Spacer(minLength: 0)
            Toggle("Active", isOn: Binding(get: { !job.isPaused }, set: { _ in onTogglePause() }))
                .labelsHidden()
                .tint(Design.Brand.accent)
        }
        .padding(Design.Spacing.md)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

struct BlueprintCard: View {
    let blueprint: CronBlueprint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                Image(systemName: blueprint.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Design.Brand.accent)
                Text(blueprint.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1)
                Text(blueprint.description)
                    .font(.caption)
                    .foregroundStyle(Design.Colors.textTertiary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(Design.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .cardSurface()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("automations.blueprint.\(blueprint.key)")
    }
}
