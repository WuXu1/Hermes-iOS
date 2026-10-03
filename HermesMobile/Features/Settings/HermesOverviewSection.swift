import SwiftUI

/// Settings header: what the paired Hermes host is running and what it has cost lately.
struct HermesOverviewSection: View {
    @Environment(AppContainer.self) private var container

    private struct AgentUsage: Identifiable {
        let name: String
        var model: String?
        var cost: Double?
        var id: String { name }
    }

    @Environment(AgentStore.self) private var agents

    @State private var status: HermesStatus?
    @State private var rows: [AgentUsage] = []
    @State private var isOffline = false

    var body: some View {
        SettingsSectionView(title: "Hermes") {
            VStack(alignment: .leading, spacing: Design.Spacing.md) {
                HStack(spacing: Design.Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Design.Brand.accent)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Design.Brand.accent.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hermes Agent")
                            .font(.headline.monospaced())
                            .foregroundStyle(Design.Colors.textPrimary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Design.Colors.textTertiary)
                    }
                    Spacer()
                    StatusPill(
                        label: isOffline ? "Offline" : (status?.gatewayRunning == false ? "Gateway off" : "Online"),
                        color: isOffline ? Design.Colors.warning : Design.Colors.success
                    )
                }

                VStack(spacing: Design.Spacing.sm) {
                    ForEach(rows) { row in
                        let style = RoleStyle.forProfile(row.name)
                        HStack(spacing: Design.Spacing.sm) {
                            RoleAvatar(style: style, size: .small, isLive: false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Design.Colors.textPrimary)
                                if let model = row.model {
                                    Text(model)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(Design.Colors.textTertiary)
                                }
                            }
                            Spacer()
                            Text(row.cost.map(Self.money) ?? "-")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Design.Colors.textSecondary)
                        }
                    }
                    if !rows.isEmpty {
                        Divider().overlay(Design.Colors.hairline)
                        HStack {
                            Text("Total, 7 days")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Design.Colors.textPrimary)
                            Spacer()
                            Text(Self.money(rows.compactMap(\.cost).reduce(0, +)))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Design.Colors.textPrimary)
                        }
                    }
                }

                Text("This iPhone is paired with your Hermes server. To unpair a lost phone, revoke it on the server (see the runbook).")
                    .font(.caption)
                    .foregroundStyle(Design.Colors.textTertiary)
            }
        }
        .task { await load() }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let version = status?.version { parts.append("Hermes \(version)") }
        if let profiles = status?.profiles, profiles.count > 1 { parts.append("\(profiles.count) profiles") }
        return parts.isEmpty ? "Your Hermes host" : parts.joined(separator: " · ")
    }

    private static func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    private static func usage(for name: String, api: HermesWorkspaceAPI) async -> AgentUsage {
        let model = try? await api.modelInfo(profile: name)
        let usage = try? await api.usage(days: 7, profile: name)
        return AgentUsage(name: name, model: model?.model, cost: usage?.totals.totalEstimatedCost)
    }

    private func load() async {
        let api = container.workspaceAPI
        do {
            status = try await api.status()
            isOffline = false
        } catch {
            isOffline = true
            return
        }
        let names = agents.ordered.map(\.name)
        let tasks = names.map { name in Task { await Self.usage(for: name, api: api) } }
        var loaded: [AgentUsage] = []
        for task in tasks { loaded.append(await task.value) }
        rows = loaded
    }

    private static let providerNames = [
        "deepseek": "DeepSeek", "openai": "OpenAI", "openrouter": "OpenRouter",
        "anthropic": "Anthropic", "nous": "Nous", "xai": "xAI", "gemini": "Gemini",
    ]

    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...: String(format: "%.1fM", Double(value) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        case 1_000...: String(format: "%.0fK", Double(value) / 1_000)
        default: "\(value)"
        }
    }
}
