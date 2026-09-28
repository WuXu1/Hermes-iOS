import SwiftUI

/// All chats with Hermes: switch, rename, delete, or start a new one.
struct HistorySheet: View {
    @Environment(ConversationsStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var renaming: ConversationSummary?
    @State private var renameText = ""
    @State private var deleting: ConversationSummary?

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
                if store.conversations.isEmpty && !store.isLoading {
                    EmptyStateView(systemImage: "bubble.left.and.bubble.right", title: "No chats yet", message: "Your conversations with Hermes will show up here.")
                } else if !query.isEmpty && store.grouped(query: query).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search chats")
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        run { try await store.startNew() }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New chat")
                }
            }
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
            .alert("Rename chat", isPresented: renameBinding) {
                TextField("Title", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    guard let conversation = renaming else { return }
                    let title = renameText
                    Task {
                        do { try await store.rename(conversation, to: title) } catch { toasts.showError(error.localizedDescription) }
                    }
                }
            }
            .confirmationDialog("Delete this chat?", isPresented: deleteBinding, titleVisibility: .visible, presenting: deleting) { conversation in
                Button("Delete", role: .destructive) {
                    Task {
                        do { try await store.archive(conversation) } catch { toasts.showError(error.localizedDescription) }
                    }
                }
            } message: { conversation in
                Text("“\(conversation.title)” will be removed from your chats.")
            }
        }
    }

    private func row(_ conversation: ConversationSummary) -> some View {
        Button {
            run(dismissAfter: true) { try await store.activate(conversation) }
        } label: {
            HStack(alignment: .top, spacing: Design.Spacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Design.Spacing.xs) {
                        Text(conversation.title)
                            .font(.body.weight(conversation.isCurrent ? .semibold : .regular))
                            .foregroundStyle(Design.Colors.textPrimary)
                            .lineLimit(1)
                        if conversation.isCurrent {
                            StatusPill(label: "Current", color: Design.Brand.accent)
                        }
                    }
                    if !conversation.preview.isEmpty {
                        Text(conversation.preview)
                            .font(.subheadline)
                            .foregroundStyle(Design.Colors.textTertiary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Text(RelativeTime.short(conversation.lastMessageAt))
                    .font(.caption)
                    .foregroundStyle(Design.Colors.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Design.Colors.surfaceSolid)
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = conversation }
            Button("Rename", systemImage: "pencil") {
                renameText = conversation.title
                renaming = conversation
            }
            .tint(Design.Colors.textTertiary)
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                renameText = conversation.title
                renaming = conversation
            }
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = conversation }
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
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
