import SwiftUI

/// The selected agent's chats from Hermes: switch, rename, archive, or start a new one.
struct HistorySheet: View {
    @Environment(ConversationsStore.self) private var store
    @Environment(AgentStore.self) private var agents
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var renaming: HermesSessionSummary?
    @State private var renameText = ""
    @State private var archiving: HermesSessionSummary?

    var body: some View {
        NavigationStack {
            List {
                if store.isOffline {
                    OfflineBanner(message: "Can't reach the relay — showing saved chats")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(store.grouped(query: query)) { group in
                    Section(group.title) {
                        ForEach(group.items) { conversation in
                            row(conversation)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Design.Colors.canvas)
            .overlay {
                if store.sessions.isEmpty && !store.isLoading {
                    EmptyStateView(systemImage: "bubble.left.and.bubble.right", title: "No chats yet", message: "Chats with \(agents.selectedLabel), from the app, Telegram and the Mac app, show up here.")
                } else if !query.isEmpty && store.grouped(query: query).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search chats")
            .navigationTitle("\(agents.selectedLabel) chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        run { try await store.startNew(profile: agents.selected) }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New chat")
                }
            }
            .refreshable { await store.refresh(profile: agents.selected) }
            .task { await store.refresh(profile: agents.selected) }
            .alert("Rename chat", isPresented: renameBinding) {
                TextField("Title", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    guard let conversation = renaming else { return }
                    let title = renameText
                    Task {
                        do { try await store.rename(conversation, to: title, profile: agents.selected) } catch { toasts.showError(error.localizedDescription) }
                    }
                }
            }
            .confirmationDialog("Archive this chat?", isPresented: archiveBinding, titleVisibility: .visible, presenting: archiving) { conversation in
                Button("Archive", role: .destructive) {
                    Task {
                        do { try await store.archive(conversation, profile: agents.selected) } catch { toasts.showError(error.localizedDescription) }
                    }
                }
            } message: { conversation in
                Text("“\(conversation.displayTitle)” will be hidden from your chats. Hermes keeps it.")
            }
        }
    }

    private func row(_ conversation: HermesSessionSummary) -> some View {
        Button {
            run(dismissAfter: true) { try await store.open(conversation, profile: agents.selected) }
        } label: {
            HStack(alignment: .top, spacing: Design.Spacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Design.Spacing.xs) {
                        Text(conversation.displayTitle)
                            .font(.body.weight(conversation.id == store.currentSessionID ? .semibold : .regular))
                            .foregroundStyle(Design.Colors.textPrimary)
                            .lineLimit(1)
                        if conversation.id == store.currentSessionID {
                            StatusPill(label: "Current", color: Design.Brand.accent)
                        }
                        if let label = conversation.sourceLabel, label != "App" {
                            StatusPill(label: label, color: Design.Colors.textTertiary)
                        }
                    }
                    if let preview = conversation.preview, !preview.isEmpty {
                        Text(preview)
                            .font(.subheadline)
                            .foregroundStyle(Design.Colors.textTertiary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Text(RelativeTime.short(conversation.lastActive))
                    .font(.caption)
                    .foregroundStyle(Design.Colors.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Design.Colors.surfaceSolid)
        .swipeActions(edge: .trailing) {
            Button("Archive", systemImage: "archivebox", role: .destructive) { archiving = conversation }
            Button("Rename", systemImage: "pencil") {
                renameText = conversation.displayTitle
                renaming = conversation
            }
            .tint(Design.Colors.textTertiary)
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                renameText = conversation.displayTitle
                renaming = conversation
            }
            Button("Archive", systemImage: "archivebox", role: .destructive) { archiving = conversation }
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var archiveBinding: Binding<Bool> {
        Binding(get: { archiving != nil }, set: { if !$0 { archiving = nil } })
    }

    private func run(dismissAfter: Bool = true, _ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
                if dismissAfter { dismiss() }
            } catch {
                toasts.showError(error.localizedDescription)
            }
        }
    }
}
