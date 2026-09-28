import SwiftUI

/// Give a task to one of the team's roles.
struct NewTaskSheet: View {
    var prefill: KanbanTaskDraft?

    @Environment(TeamStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(TabRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var details = ""
    @State private var assignee: String?
    @State private var reviewAfter = false
    @State private var isSubmitting = false
    @FocusState private var focusedField: Field?

    private enum Field { case title, details }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                        TextField("What should be done?", text: $title, axis: .vertical)
                            .font(.title3.weight(.semibold))
                            .focused($focusedField, equals: .title)
                            .accessibilityIdentifier("newTask.title")
                        ZStack(alignment: .topLeading) {
                            if details.isEmpty {
                                Text("Details, links and constraints. Workers only see what you write here.")
                                    .font(.subheadline)
                                    .foregroundStyle(Design.Colors.textTertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            TextEditor(text: $details)
                                .font(.subheadline)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 110)
                                .focused($focusedField, equals: .details)
                        }
                    }
                    .padding(Design.Spacing.md)
                    .cardSurface()

                    VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                        SectionHeader(title: "Who should do it?")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Design.Spacing.sm) {
                            ForEach(store.assignableRoles) { profile in
                                roleCard(profile)
                            }
                        }
                    }

                    if assignee != "reviewer" {
                        Toggle(isOn: $reviewAfter) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Have the reviewer check it")
                                    .font(.subheadline.weight(.semibold))
                                Text("Adds a review task that starts when this one is done.")
                                    .font(.caption)
                                    .foregroundStyle(Design.Colors.textTertiary)
                            }
                        }
                        .tint(RoleStyle.forProfile("reviewer").color)
                        .padding(Design.Spacing.md)
                        .cardSurface()
                    }
                }
                .padding(Design.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Design.Colors.canvas)
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Assign", action: submit)
                            .disabled(!canSubmit)
                            .accessibilityIdentifier("newTask.submit")
                    }
                }
            }
            .onAppear(perform: applyPrefill)
            .task {
                if store.profiles.isEmpty { await store.refresh() }
                if assignee == nil { assignee = store.assignableRoles.first?.name }
            }
        }
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && assignee != nil
    }

    private func roleCard(_ profile: HermesProfile) -> some View {
        let style = RoleStyle.forProfile(profile.name)
        let isSelected = assignee == profile.name
        return Button {
            withAnimation(Design.Motion.quickResponse) { assignee = profile.name }
        } label: {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                HStack {
                    RoleAvatar(style: style, size: .small)
                    Text(style.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Design.Colors.textPrimary)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(style.color)
                    }
                }
                Text(profile.description?.isEmpty == false ? profile.description! : "A member of your Hermes team.")
                    .font(.caption)
                    .foregroundStyle(Design.Colors.textTertiary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Design.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Design.CornerRadius.md, style: .continuous)
                    .fill(isSelected ? style.color.opacity(0.12) : Design.Colors.surfaceSolid)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.CornerRadius.md, style: .continuous)
                    .strokeBorder(isSelected ? style.color.opacity(0.7) : Design.Colors.hairline, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("newTask.role.\(profile.name)")
    }

    private func applyPrefill() {
        guard let prefill, title.isEmpty else {
            if title.isEmpty { focusedField = .title }
            return
        }
        title = prefill.title
        details = prefill.body ?? ""
        assignee = prefill.assignee
    }

    private func submit() {
        guard let assignee else { return }
        let draft = KanbanTaskDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : details,
            assignee: assignee
        )
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let task = try await store.create(draft, reviewAfter: reviewAfter && assignee != "reviewer")
                dismiss()
                let router = router
                toasts.show("Assigned to \(RoleStyle.forProfile(assignee).displayName)", systemImage: "person.badge.plus", actionTitle: "View") {
                    router.show(TaskRoute(id: task.id), in: .team)
                }
            } catch {
                toasts.showError(error.localizedDescription)
            }
        }
    }
}
