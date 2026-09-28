import SwiftUI

struct TaskDetailScreen: View {
    let taskID: String

    @Environment(TeamStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var detail: KanbanTaskDetail?
    @State private var loadError: String?
    @State private var isBriefExpanded = false
    @State private var composer: ComposerMode?
    @State private var openedAttachment: KanbanAttachment?
    @State private var confirmDelete = false
    @State private var isWorking = false

    enum ComposerMode: String, Identifiable {
        case reply, requestChanges
        var id: String { rawValue }
    }

    /// Board data refreshes live; fall back to the fetched detail.
    private var task: KanbanTask? { store.task(id: taskID) ?? detail?.task }

    var body: some View {
        Group {
            if let task {
                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                        header(task)
                        if task.status == .blocked { blockedCallout(task) }
                        resultCard(task)
                        briefCard(task)
                        if let detail, !detail.attachments.isEmpty { attachments(detail.attachments) }
                        activity(task)
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.top, Design.Spacing.xs)
                    .padding(.bottom, 140)
                }
                .safeAreaInset(edge: .bottom) { actionBar(task) }
            } else if let loadError {
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load this task", message: loadError)
            } else {
                ProgressView().tint(Design.Brand.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .canvasBackground(glowOpacity: 0.06)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if let task { menu(task) } }
        .task(id: taskID) { await load() }
        .refreshable { await load() }
        .sheet(item: $composer) { mode in
            if let task { composerSheet(mode, task: task) }
        }
        .sheet(item: $openedAttachment) { attachment in
            AttachmentSheet(attachment: attachment)
        }
        .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let task else { return }
                perform("Task deleted", systemImage: "trash") {
                    try await store.delete(task)
                    dismiss()
                }
            }
        } message: {
            Text("The task, its comments and its attachments are removed from the board.")
        }
    }

    // MARK: Sections

    private func header(_ task: KanbanTask) -> some View {
        let style = RoleStyle.forProfile(task.assignee)
        return HStack(alignment: .top, spacing: Design.Spacing.sm) {
            RoleAvatar(style: style, size: .large, isLive: task.status == .running)
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(task.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Design.Spacing.xs) {
                    task.status.pill
                    Text(style.displayName)
                        .font(.caption)
                        .foregroundStyle(style.color)
                    Text(RelativeTime.short(task.createdAt))
                        .font(.caption)
                        .foregroundStyle(Design.Colors.textTertiary)
                }
            }
        }
    }

    private func blockedCallout(_ task: KanbanTask) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Label("Waiting on you", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Design.Colors.warning)
            Text(task.lastFailureError ?? task.latestSummary ?? "The worker stopped and needs your input to continue.")
                .font(.subheadline)
                .foregroundStyle(Design.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Design.CornerRadius.lg, style: .continuous)
                .fill(Design.Colors.warning.opacity(0.1))
        )
    }

    @ViewBuilder
    private func resultCard(_ task: KanbanTask) -> some View {
        if let text = task.result ?? task.latestSummary, task.status != .blocked {
            card(title: task.status == .done ? "Result" : "Latest update", symbol: "text.alignleft") {
                MarkdownContentView(content: text, isStreaming: false)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func briefCard(_ task: KanbanTask) -> some View {
        if let body = task.body, !body.isEmpty {
            card(title: "Brief", symbol: "doc.text") {
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(Design.Colors.textSecondary)
                        .lineLimit(isBriefExpanded ? nil : 6)
                        .textSelection(.enabled)
                    if body.split(whereSeparator: \.isNewline).count > 6 || body.count > 360 {
                        Button(isBriefExpanded ? "Show less" : "Show more") {
                            withAnimation(Design.Motion.standard) { isBriefExpanded.toggle() }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Design.Brand.accent)
                    }
                }
            }
        }
    }

    private func attachments(_ attachments: [KanbanAttachment]) -> some View {
        card(title: "Attachments", symbol: "paperclip") {
            VStack(spacing: 0) {
                ForEach(attachments) { attachment in
                    Button { openedAttachment = attachment } label: {
                        HStack(spacing: Design.Spacing.sm) {
                            Image(systemName: attachment.isImage ? "photo" : attachment.isText ? "doc.plaintext" : "doc")
                                .foregroundStyle(Design.Brand.accent)
                                .frame(width: 22)
                            Text(attachment.filename)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Design.Colors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if let size = attachment.size {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(Design.Colors.textTertiary)
                            }
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
        }
    }

    private func activity(_ task: KanbanTask) -> some View {
        card(title: "Activity", symbol: "clock") {
            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                ForEach(timeline) { entry in
                    HStack(alignment: .top, spacing: Design.Spacing.sm) {
                        Circle()
                            .fill(entry.isComment ? Design.Brand.accent : Design.Colors.textTertiary)
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.subheadline.weight(entry.isComment ? .semibold : .regular))
                                .foregroundStyle(Design.Colors.textPrimary)
                            if let body = entry.body {
                                Text(body)
                                    .font(.subheadline)
                                    .foregroundStyle(Design.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(RelativeTime.short(entry.date))
                                .font(.caption2)
                                .foregroundStyle(Design.Colors.textTertiary)
                        }
                    }
                }
                NavigationLink {
                    TaskLogScreen(taskID: task.id)
                } label: {
                    Label("Worker log", systemImage: "terminal")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Design.Brand.accent)
                }
                .padding(.top, Design.Spacing.xxs)
            }
        }
    }

    // MARK: Actions

    @ViewBuilder
    private func actionBar(_ task: KanbanTask) -> some View {
        let buttons = Group {
            switch task.status {
            case .blocked:
                primaryButton("Reply and unblock", systemImage: "arrowshape.turn.up.left.fill") { composer = .reply }
            case .review:
                HStack(spacing: Design.Spacing.sm) {
                    secondaryButton("Request changes") { composer = .requestChanges }
                    primaryButton("Approve", systemImage: "checkmark") {
                        perform("Approved", systemImage: "checkmark.seal.fill") { try await store.approve(task) }
                    }
                }
            case .running, .ready, .todo, .triage, .scheduled:
                secondaryButton("Add a note for the worker") { composer = .reply }
            default:
                EmptyView()
            }
        }
        if task.status.isOpen {
            buttons
                .disabled(isWorking)
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
        }
    }

    private func menu(_ task: KanbanTask) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if task.status.isOpen {
                    Menu("Reassign") {
                        ForEach(store.assignableRoles.filter { $0.name != task.assignee }) { profile in
                            Button(RoleStyle.forProfile(profile.name).displayName) {
                                perform("Reassigned to \(RoleStyle.forProfile(profile.name).displayName)", systemImage: "arrow.triangle.swap") {
                                    try await store.reassign(task, to: profile.name)
                                }
                            }
                        }
                    }
                    Button("Mark done", systemImage: "checkmark.circle") {
                        perform("Marked done", systemImage: "checkmark.circle.fill") { try await store.markDone(task) }
                    }
                }
                Button("Copy task ID", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = task.id
                    toasts.show("Copied \(task.id)", systemImage: "doc.on.doc")
                }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("Task actions")
        }
    }

    private func composerSheet(_ mode: ComposerMode, task: KanbanTask) -> some View {
        let isChanges = mode == .requestChanges
        let isBlocked = task.status == .blocked
        return NoteComposerSheet(
            title: isChanges ? "Request changes" : isBlocked ? "Reply and unblock" : "Note for the worker",
            prompt: isChanges
                ? "What should be fixed? The worker will see this and pick the task back up."
                : isBlocked
                    ? "Tell the worker what you did or what to do next. The task goes back in the queue."
                    : "The worker reads notes when it next checks the task.",
            actionTitle: isChanges ? "Send back" : isBlocked ? "Unblock" : "Add note"
        ) { text in
            perform(isChanges ? "Sent back with notes" : isBlocked ? "Unblocked" : "Note added", systemImage: "paperplane.fill") {
                if isChanges {
                    try await store.requestChanges(task, notes: text)
                } else {
                    try await store.reply(to: task, with: text)
                }
                await load()
            }
        }
    }

    private func perform(_ success: String, systemImage: String, _ operation: @escaping () async throws -> Void) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await operation()
                toasts.show(success, systemImage: systemImage)
            } catch {
                toasts.showError(error.localizedDescription)
            }
        }
    }

    private func load() async {
        do {
            detail = try await store.detail(for: taskID)
            loadError = nil
        } catch {
            if detail == nil { loadError = error.localizedDescription }
        }
    }

    // MARK: Building blocks

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

    private func primaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.xs)
        }
        .buttonStyle(.glassProminent)
        .tint(Design.Brand.accent)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.xs)
        }
        .buttonStyle(.glass)
    }

    // MARK: Timeline

    private struct TimelineEntry: Identifiable {
        let id: String
        let title: String
        let body: String?
        let date: Date?
        let isComment: Bool
    }

    private var timeline: [TimelineEntry] {
        guard let detail else { return [] }
        let events = detail.events.compactMap { event -> TimelineEntry? in
            guard let title = Self.describe(event) else { return nil }
            return TimelineEntry(id: "e\(event.id)", title: title, body: nil, date: event.createdAt, isComment: false)
        }
        let comments = detail.comments.map { comment in
            TimelineEntry(
                id: "c\(comment.id)",
                title: comment.author.map { $0 == "you" || $0 == "dashboard" ? "You" : RoleStyle.forProfile($0).displayName } ?? "Comment",
                body: comment.body,
                date: comment.createdAt,
                isComment: true
            )
        }
        return (events + comments).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private static func describe(_ event: KanbanEvent) -> String? {
        let assignee = event.payload?["assignee"]?.stringValue.map { RoleStyle.forProfile($0).displayName }
        switch event.kind {
        case "created": return assignee.map { "Created for \($0)" } ?? "Created"
        case "claimed", "spawned": return "Picked up"
        case "completed": return "Completed"
        case "blocked": return "Blocked"
        case "unblocked": return "Unblocked"
        case "review_requested": return "Ready for review"
        case "changes_requested": return "Changes requested"
        case "reassigned", "assigned": return assignee.map { "Assigned to \($0)" } ?? "Reassigned"
        case "crashed": return "Worker crashed"
        case "gave_up": return "Gave up after retries"
        case "edited": return "Edited"
        case "heartbeat", "tip_scratch_workspace": return nil
        default: return event.kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// A small sheet for writing a note, reply or change request.
struct NoteComposerSheet: View {
    let title: String
    let prompt: String
    let actionTitle: String
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                Text(prompt)
                    .font(.subheadline)
                    .foregroundStyle(Design.Colors.textSecondary)
                TextEditor(text: $text)
                    .focused($isFocused)
                    .scrollContentBackground(.hidden)
                    .padding(Design.Spacing.xs)
                    .frame(minHeight: 140)
                    .background(
                        RoundedRectangle(cornerRadius: Design.CornerRadius.md, style: .continuous)
                            .fill(Design.Colors.surfaceRaised)
                    )
                Spacer()
            }
            .padding(Design.Spacing.md)
            .background(Design.Colors.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) {
                        onSubmit(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
