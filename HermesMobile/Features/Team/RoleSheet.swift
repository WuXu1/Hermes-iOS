import SwiftUI

/// A role's details: what it's for, what it's working on, and its persona.
struct RoleSheet: View {
    let profile: HermesProfile

    @Environment(TeamStore.self) private var store
    @Environment(AgentStore.self) private var agents
    @Environment(TabRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    private var style: RoleStyle { RoleStyle.forProfile(profile.name) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    VStack(spacing: Design.Spacing.sm) {
                        RoleAvatar(style: style, size: .large, isLive: store.activity(for: profile.name).isWorking)
                        Text(agents.label(for: profile.name))
                            .font(.title2.weight(.bold))
                        if let model = profile.model {
                            Text(model)
                                .font(.caption.monospaced())
                                .foregroundStyle(Design.Colors.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    stats

                    if !profile.isDefault {
                        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                            SectionHeader(title: "What this role is for")
                            Text(profile.description ?? "")
                                .font(.subheadline)
                                .foregroundStyle(Design.Colors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Design.Spacing.sm)
                                .cardSurface(cornerRadius: Design.CornerRadius.md)
                            Text("The chief of staff uses this to decide who gets which task.")
                                .font(.caption)
                                .foregroundStyle(Design.Colors.textTertiary)
                        }
                    }

                    VStack(spacing: 0) {
                        NavigationLink {
                            PersonaEditorScreen(profile: profile)
                        } label: {
                            row("Persona", systemImage: "person.text.rectangle", detail: "How this role thinks and works")
                        }
                        if !profile.isDefault {
                            Divider().overlay(Design.Colors.hairline)
                            Button {
                                dismiss()
                                router.presentSheet(.newTask(prefill: KanbanTaskDraft(title: "", assignee: profile.name)))
                            } label: {
                                row("Give \(agents.label(for: profile.name)) a task", systemImage: "plus.circle", detail: nil)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .cardSurface()
                }
                .padding(Design.Spacing.md)
            }
            .background(Design.Colors.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private var stats: some View {
        let tasks = store.board.allTasks.filter { $0.assignee == profile.name }
        let values = [
            ("Working", tasks.filter { $0.status == .running }.count),
            ("Waiting", tasks.filter { [.ready, .todo, .triage, .scheduled, .blocked, .review].contains($0.status) }.count),
            ("Done", tasks.filter { $0.status == .done }.count),
        ]
        return HStack(spacing: Design.Spacing.sm) {
            ForEach(values, id: \.0) { label, value in
                VStack(spacing: 2) {
                    Text("\(value)")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .fontDesign(.rounded)
                        .foregroundStyle(value > 0 && label == "Working" ? style.color : Design.Colors.textPrimary)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(Design.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.sm)
                .cardSurface(cornerRadius: Design.CornerRadius.md)
            }
        }
    }

    private func row(_ title: String, systemImage: String, detail: String?) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(style.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Design.Colors.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Design.Colors.textTertiary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Design.Colors.textTertiary)
        }
        .padding(Design.Spacing.md)
        .contentShape(Rectangle())
    }
}

/// A role's SOUL.md persona, read-only.
struct PersonaEditorScreen: View {
    let profile: HermesProfile

    /// First line the server's deploy script adds to personas it manages.
    static let managedMarker = "<!-- managed by hermes-host; delete this line to keep your own edits across redeploys -->"

    @Environment(TeamStore.self) private var store
    @State private var content: String?
    @State private var error: String?

    var body: some View {
        Group {
            if let content {
                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing.md) {
                        Text(content)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Personas hold the house rules, so they're changed on the server, not from the phone.")
                            .font(.caption)
                            .foregroundStyle(Design.Colors.textTertiary)
                    }
                    .padding(Design.Spacing.md)
                }
            } else if let error {
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load the persona", message: error)
            } else {
                ProgressView().tint(Design.Brand.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Design.Colors.canvas)
        .navigationTitle("Persona")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                content = Self.displayText(try await store.soul(for: profile.name))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Hide the machine marker.
    private static func displayText(_ soul: String) -> String {
        guard soul.hasPrefix(managedMarker) else { return soul }
        return String(soul.dropFirst(managedMarker.count)).trimmingCharacters(in: .newlines)
    }
}
