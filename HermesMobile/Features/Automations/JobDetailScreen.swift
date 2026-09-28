import SwiftUI

struct JobDetailScreen: View {
    let jobID: String

    @Environment(AutomationsStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var runs: [CronRun]?
    @State private var runsError: String?
    @State private var confirmDelete = false

    private var job: CronJob? { store.jobs.first { $0.id == jobID } }

    var body: some View {
        Group {
            if let job {
                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                        header(job)
                        actions(job)
                        card(title: "What Hermes does", symbol: "text.quote") {
                            Text(job.prompt)
                                .font(.subheadline)
                                .foregroundStyle(Design.Colors.textSecondary)
                                .textSelection(.enabled)
                        }
                        if let error = job.lastError, !error.isEmpty {
                            card(title: "Last error", symbol: "exclamationmark.triangle") {
                                Text(error)
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(Design.Colors.danger)
                            }
                        }
                        runsCard
                    }
                    .padding(Design.Spacing.md)
                    .padding(.bottom, 100)
                }
            } else {
                EmptyStateView(systemImage: "clock", title: "Automation not found", message: "It may have been deleted.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .canvasBackground(glowOpacity: 0.06)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: CronRun.self) { run in
            RunOutputScreen(run: run)
        }
        .task(id: jobID) { await loadRuns() }
        .refreshable {
            await store.refresh()
            await loadRuns()
        }
        .confirmationDialog("Delete this automation?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let job else { return }
                Task {
                    do {
                        try await store.delete(job)
                        dismiss()
                        toasts.show("Automation deleted", systemImage: "trash")
                    } catch {
                        toasts.showError(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func header(_ job: CronJob) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text(job.displayName)
                .font(.title2.weight(.bold))
                .foregroundStyle(Design.Colors.textPrimary)
            Label(job.scheduleText, systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(Design.Colors.textSecondary)
            HStack(spacing: Design.Spacing.xs) {
                StatusPill(
                    label: job.isPaused ? "Paused" : "Active",
                    color: job.isPaused ? Design.Colors.textTertiary : Design.Colors.success,
                    systemImage: job.isPaused ? "pause.fill" : "play.fill"
                )
                if !job.isPaused, job.nextRunAt != nil {
                    Text("Next \(RelativeTime.future(job.nextRunAt))")
                        .font(.caption)
                        .foregroundStyle(Design.Colors.textTertiary)
                }
                if let profile = job.profile {
                    Text("· \(RoleStyle.forProfile(profile).displayName)")
                        .font(.caption)
                        .foregroundStyle(RoleStyle.forProfile(profile).color)
                }
            }
        }
    }

    private func actions(_ job: CronJob) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Button {
                Task {
                    do {
                        try await store.runNow(job)
                        toasts.show("Running now — check back in a minute", systemImage: "play.circle.fill")
                    } catch {
                        toasts.showError(error.localizedDescription)
                    }
                }
            } label: {
                Label("Run now", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Design.Brand.accent)

            Button {
                Task {
                    do {
                        try await store.togglePause(job)
                    } catch {
                        toasts.showError(error.localizedDescription)
                    }
                }
            } label: {
                Label(job.isPaused ? "Resume" : "Pause", systemImage: job.isPaused ? "play" : "pause")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)

            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Delete automation")
        }
    }

    private var runsCard: some View {
        card(title: "Recent runs", symbol: "clock.arrow.circlepath") {
            if let runs, runs.isEmpty {
                Text("No runs yet. Use Run now to try it.")
                    .font(.subheadline)
                    .foregroundStyle(Design.Colors.textTertiary)
            } else if let runs {
                VStack(spacing: 0) {
                    ForEach(runs) { run in
                        NavigationLink(value: run) {
                            HStack(spacing: Design.Spacing.sm) {
                                Image(systemName: run.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundStyle(run.succeeded ? Design.Colors.success : Design.Colors.danger)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(run.startedAt?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()) ?? run.id)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Design.Colors.textPrimary)
                                    if let cost = run.estimatedCostUSD {
                                        Text(cost.formatted(.currency(code: "USD").precision(.fractionLength(4))))
                                            .font(.caption)
                                            .foregroundStyle(Design.Colors.textTertiary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Design.Colors.textTertiary)
                            }
                            .padding(.vertical, Design.Spacing.xs)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if let runsError {
                Text(runsError)
                    .font(.footnote)
                    .foregroundStyle(Design.Colors.danger)
            } else {
                ProgressView().tint(Design.Brand.accent)
            }
        }
    }

    private func card<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Design.Colors.textTertiary)
                .textCase(.uppercase)
            content()
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func loadRuns() async {
        guard let job else { return }
        do {
            runs = try await store.runs(for: job)
            runsError = nil
        } catch {
            runsError = error.localizedDescription
        }
    }
}

/// One run's output: the final reply Hermes produced.
struct RunOutputScreen: View {
    let run: CronRun

    @Environment(AutomationsStore.self) private var store
    @State private var output: String?
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.md) {
                if let output {
                    MarkdownContentView(content: output, isStreaming: false)
                        .textSelection(.enabled)
                } else if let error {
                    EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load this run", message: error)
                } else if loaded {
                    EmptyStateView(systemImage: "text.page.slash", title: "No output", message: "This run didn't produce a reply.")
                } else {
                    ProgressView().tint(Design.Brand.accent).frame(maxWidth: .infinity)
                }
            }
            .padding(Design.Spacing.md)
        }
        .background(Design.Colors.canvas)
        .navigationTitle(run.startedAt?.formatted(.dateTime.day().month(.abbreviated).hour().minute()) ?? "Run")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let output {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: output) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .task {
            do {
                output = try await store.output(for: run)
            } catch {
                self.error = error.localizedDescription
            }
            loaded = true
        }
    }
}
