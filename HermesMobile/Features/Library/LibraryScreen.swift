import SwiftUI

struct LibraryScreen: View {
    enum Section: String, CaseIterable {
        case memory = "Memory"
        case skills = "Skills"
    }

    @Environment(LibraryStore.self) private var store
    @State private var section: Section = .memory

    var body: some View {
        @Bindable var store = store
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Design.Spacing.lg) {
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                if store.isOffline {
                    OfflineBanner { Task { await store.refresh() } }
                }

                if !store.hasLoaded {
                    ProgressView()
                        .tint(Design.Brand.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Design.Spacing.xxl)
                } else {
                    switch section {
                    case .memory: memory
                    case .skills: SkillsListView()
                    }
                }
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.top, Design.Spacing.xs)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .canvasBackground()
        .navigationTitle("Library")
        .navigationDestination(for: HermesMemoryKind.self) { kind in
            MemoryEditorScreen(kind: kind)
        }
        .navigationDestination(for: HermesSkill.self) { skill in
            SkillDetailScreen(skill: skill)
        }
        .searchable(text: $store.skillQuery, prompt: "Search skills")
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .onChange(of: store.skillQuery) { _, query in
            if !query.isEmpty { section = .skills }
        }
        .refreshable { await store.refresh() }
        .task { await store.refresh() }
    }

    private var memory: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("Hermes keeps these notes between chats and uses them as context. Edit them to correct or add anything.")
                .font(.footnote)
                .foregroundStyle(Design.Colors.textTertiary)
            ForEach(HermesMemoryKind.allCases) { kind in
                NavigationLink(value: kind) {
                    MemoryCardView(kind: kind, document: store.memory[kind])
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("library.memory.\(kind.rawValue)")
            }
        }
    }
}

struct MemoryCardView: View {
    let kind: HermesMemoryKind
    let document: HermesMemoryDocument

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Design.Brand.accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Design.Brand.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.headline)
                        .foregroundStyle(Design.Colors.textPrimary)
                    Text(document.updatedAt.map { "Updated \(RelativeTime.short($0))" } ?? kind.subtitle)
                        .font(.caption)
                        .foregroundStyle(Design.Colors.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Design.Colors.textTertiary)
            }
            if document.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Nothing saved yet. Hermes adds notes here as it learns — or write your own.")
                    .font(.subheadline)
                    .foregroundStyle(Design.Colors.textTertiary)
            } else {
                Text(document.content.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.subheadline)
                    .foregroundStyle(Design.Colors.textSecondary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Design.Spacing.md)
        .cardSurface()
    }
}

/// View and edit one memory file.
struct MemoryEditorScreen: View {
    let kind: HermesMemoryKind

    @Environment(LibraryStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @State private var content = ""
    @State private var isEditing = false
    @State private var isSaving = false

    private var bytes: Int { content.utf8.count }
    private var isTooLarge: Bool { bytes > HermesMemoryKind.maxBytes }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            if isEditing {
                TextEditor(text: $content)
                    .font(.system(.subheadline, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(Design.Spacing.xs)
                    .cardSurface(cornerRadius: Design.CornerRadius.md)
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) of 64 KB")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isTooLarge ? Design.Colors.danger : Design.Colors.textTertiary)
            } else {
                ScrollView {
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        EmptyStateView(
                            systemImage: kind.symbol,
                            title: "Nothing here yet",
                            message: "Hermes hasn't saved anything in \(kind.title.lowercased()). Tap Edit to write something yourself.",
                            actionTitle: "Edit"
                        ) {
                            isEditing = true
                        }
                    } else {
                        MarkdownContentView(content: content, isStreaming: false)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(Design.Spacing.md)
        .background(Design.Colors.canvas)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isEditing {
                    Button(isSaving ? "Saving…" : "Save", action: save)
                        .disabled(isSaving || isTooLarge)
                } else {
                    Button("Edit") { isEditing = true }
                }
            }
            if isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        content = store.memory[kind].content
                        isEditing = false
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(isEditing)
        .onAppear { content = store.memory[kind].content }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await store.save(kind, content: content)
                isEditing = false
                toasts.show("Memory saved", systemImage: "brain")
            } catch {
                toasts.showError(error.localizedDescription)
            }
        }
    }
}
