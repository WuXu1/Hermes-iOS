import SwiftUI

/// Installed skills grouped by category, with enable toggles.
struct SkillsListView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.lg) {
            Text("\(store.enabledSkillCount) of \(store.skills.count) skills on. Skills teach Hermes how to do specific jobs; switched-off skills are never loaded.")
                .font(.footnote)
                .foregroundStyle(Design.Colors.textTertiary)

            if store.skillsByCategory.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass", title: "No matching skills", message: "Try a different search.")
            }

            ForEach(store.skillsByCategory) { group in
                VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                    SectionHeader(title: group.title, count: group.skills.count)
                    VStack(spacing: 0) {
                        ForEach(group.skills) { skill in
                            row(skill)
                            if skill.id != group.skills.last?.id {
                                Divider().overlay(Design.Colors.hairline).padding(.leading, Design.Spacing.md)
                            }
                        }
                    }
                    .cardSurface()
                }
            }
        }
    }

    private func row(_ skill: HermesSkill) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            NavigationLink(value: skill) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Design.Spacing.xs) {
                        Text(skill.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(skill.enabled ? Design.Colors.textPrimary : Design.Colors.textTertiary)
                        if let usage = skill.usage, usage > 0 {
                            Text("\(usage)×")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Design.Colors.textTertiary)
                        }
                    }
                    if let description = skill.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(Design.Colors.textTertiary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(skill.name, isOn: Binding(
                get: { skill.enabled },
                set: { enabled in
                    Task {
                        if !(await store.setSkill(skill, enabled: enabled)) {
                            toasts.showError(store.errorMessage ?? "Couldn't update \(skill.name).")
                        }
                    }
                }
            ))
            .labelsHidden()
            .tint(Design.Brand.accent)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
    }
}

/// A skill's SKILL.md.
struct SkillDetailScreen: View {
    let skill: HermesSkill

    @Environment(LibraryStore.self) private var store
    @State private var content: String?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.md) {
                if let description = skill.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(Design.Colors.textSecondary)
                }
                HStack(spacing: Design.Spacing.xs) {
                    StatusPill(label: skill.enabled ? "On" : "Off", color: skill.enabled ? Design.Colors.success : Design.Colors.textTertiary)
                    StatusPill(label: skill.categoryTitle, color: Design.Colors.textSecondary)
                    if let provenance = skill.provenance {
                        StatusPill(label: provenance.capitalized, color: Design.Colors.textSecondary)
                    }
                }
                Divider().overlay(Design.Colors.hairline)
                if let content {
                    MarkdownContentView(content: Self.stripFrontMatter(content), isStreaming: false)
                        .textSelection(.enabled)
                } else if let error {
                    Text(error).font(.footnote).foregroundStyle(Design.Colors.danger)
                } else {
                    ProgressView().tint(Design.Brand.accent)
                }
            }
            .padding(Design.Spacing.md)
        }
        .background(Design.Colors.canvas)
        .navigationTitle(skill.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                content = try await store.content(of: skill)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// SKILL.md starts with YAML front matter that's metadata, not reading material.
    static func stripFrontMatter(_ text: String) -> String {
        guard text.hasPrefix("---") else { return text }
        let parts = text.components(separatedBy: "\n---")
        guard parts.count > 1 else { return text }
        return parts.dropFirst().joined(separator: "\n---").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
