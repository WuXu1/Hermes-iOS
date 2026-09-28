import SwiftUI

/// Settings header: what the paired Hermes host is running and what it has cost lately.
struct HermesOverviewSection: View {
    @Environment(AppContainer.self) private var container

    @State private var status: HermesStatus?
    @State private var model: HermesModelInfo?
    @State private var usage: HermesUsage?
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
                        Text(model?.model ?? "Hermes Agent")
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

                if let usage {
                    HStack(spacing: Design.Spacing.sm) {
                        stat(usage.totals.totalEstimatedCost.formatted(.currency(code: "USD").precision(.fractionLength(2))), label: "Cost, 7 days")
                        stat("\(usage.totals.totalSessions)", label: "Sessions")
                        stat(Self.compact(usage.totals.totalInput + usage.totals.totalOutput), label: "Tokens")
                    }
                }

                if let capabilities = model?.capabilities {
                    HStack(spacing: Design.Spacing.xs) {
                        if let context = model?.effectiveContextLength {
                            StatusPill(label: "\(Self.compact(context)) context", color: Design.Colors.textSecondary)
                        }
                        if capabilities.supportsVision == true {
                            StatusPill(label: "Vision", color: Design.Colors.textSecondary, systemImage: "eye")
                        }
                        if capabilities.supportsTools == true {
                            StatusPill(label: "Tools", color: Design.Colors.textSecondary, systemImage: "wrench.and.screwdriver")
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let provider = model?.provider { parts.append(Self.providerNames[provider] ?? provider.capitalized) }
        if let version = status?.version { parts.append("Hermes \(version)") }
        if let profiles = status?.profiles, profiles.count > 1 { parts.append("\(profiles.count) profiles") }
        return parts.isEmpty ? "Your Hermes host" : parts.joined(separator: " · ")
    }

    private func stat(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(Design.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Design.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        let api = container.workspaceAPI
        do {
            async let status = api.status()
            async let model = api.modelInfo()
            async let usage = api.usage(days: 7)
            self.status = try await status
            self.model = try await model
            self.usage = try? await usage
            isOffline = false
        } catch {
            isOffline = true
        }
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
