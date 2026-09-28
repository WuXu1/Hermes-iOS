import SwiftUI

/// A role's details: what it's for, what it's working on, and its persona.
struct RoleSheet: View {
    let profile: HermesProfile

    @Environment(TeamStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(TabRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var description = ""
    @State private var isSavingDescription = false

    private var style: RoleStyle { RoleStyle.forProfile(profile.name) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    VStack(spacing: Design.Spacing.sm) {
                        RoleAvatar(style: style, size: .large, isLive: store.activity(for: profile.name).isWorking)
                        Text(style.displayName)
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
                            TextEditor(text: $description)
                                .font(.subheadline)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 90)
                                .padding(Design.Spacing.xs)
                                .cardSurface(cornerRadius: Design.CornerRadius.md)
                            Text("The chief of staff uses this to decide who gets which task.")
                                .font(.caption)
                                .foregroundStyle(Design.Colors.textTertiary)
                            if description != (profile.description ?? "") {
                                Button(isSavingDescription ? "Saving…" : "Save description", action: saveDescription)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Design.Brand.accent)
                                    .disabled(isSavingDescription)
                            }
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
                                row("Give \(style.displayName) a task", systemImage: "plus.circle", detail: nil)
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
            .onAppear { description = profile.description ?? "" }
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

    private func saveDescription() {
        isSavingDescription = true
        Task {
            defer { isSavingDescription = false }
            do {
                try await store.saveDescription(description.trimmingCharacters(in: .whitespacesAndNewlines), for: profile.name)
                toasts.show("Description saved")
            } catch {
                toasts.showError(error.localizedDescription)
            }
        }
    }
}

/// Edit a role's SOUL.md persona.
struct PersonaEditorScreen: View {
    let profile: HermesProfile

    /// First line the server's deploy script adds to personas it manages.
    static let managedMarker = "<!-- managed by hermes-host; delete this line to keep your own edits across redeploys -->"

    @Environment(TeamStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @State private var content = ""
    @State private var original: String?
    @State private var error: String?
    @State private var isSaving = false

    private var isManaged: Bool { original?.hasPrefix(Self.managedMarker) == true }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            if isManaged {
                Label(
                    "Your server's deploy manages this persona. Saving here takes it over so redeploys keep your edits.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(Design.Colors.textSecondary)
                .padding(Design.Spacing.sm)
                .background(RoundedRectangle(cornerRadius: Design.CornerRadius.md).fill(Design.Colors.surfaceSolid))
            }
            if original == nil, error == nil {
                ProgressView().tint(Design.Brand.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load the persona", message: error)
            } else {
                TextEditor(text: $content)
                    .font(.system(.footnote, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(Design.Spacing.xs)
                    .cardSurface(cornerRadius: Design.CornerRadius.md)
            }
        }
        .padding(Design.Spacing.md)
        .background(Design.Colors.canvas)
        .navigationTitle("Persona")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save", action: save)
                    .disabled(isSaving || original == nil || content == displayText(original ?? ""))
            }
        }
        .task {
            do {
                let soul = try await store.soul(for: profile.name)
                original = soul
                content = displayText(soul)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Hide the machine marker while editing.
    private func displayText(_ soul: String) -> String {
        guard soul.hasPrefix(Self.managedMarker) else { return soul }
        return String(soul.dropFirst(Self.managedMarker.count)).trimmingCharacters(in: .newlines)
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await store.saveSoul(content, for: profile.name)
                original = content
                toasts.show("Persona saved")
            } catch {
                toasts.showError(error.localizedDescription)
            }
        }
    }
}
