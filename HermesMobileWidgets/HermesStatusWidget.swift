import SwiftUI
import WidgetKit

/// Glanceable Hermes status: connection, board counts and the next automation.
struct HermesStatusWidget: Widget {
    let kind = "HermesStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HermesTimelineProvider()) { entry in
            HermesStatusView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
        }
        .configurationDisplayName("Hermes Status")
        .description("Connection, running and waiting tasks, and your next automation.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}

// MARK: - Views

private struct HermesStatusView: View {
    let entry: HermesWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            systemSmallView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            systemSmallView
        }
    }

    // MARK: - System Small (Home Screen)

    private var systemSmallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HermesBrandIcon(size: 22)
                Text("Hermes")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Circle()
                    .fill(entry.data.hostOnline ? .green : .gray)
                    .frame(width: 8, height: 8)
            }

            Spacer()

            boardCounts
                .font(.caption.weight(.medium))

            if let automation = nextAutomationText {
                Text(automation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let preview = entry.data.lastMessagePreview {
                Text(preview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(entry.data.hostOnline ? "Ready" : "Offline")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let nextAt = entry.data.nextAutomationAt, nextAutomationText != nil, nextAt > entry.date {
                Text(nextAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .widgetURL(URL(string: "hermes://chat"))
    }

    // MARK: - Shared pieces

    /// "2 running · 1 needs you", with the second part highlighted.
    private var boardCounts: some View {
        HStack(spacing: 4) {
            Text("\(entry.data.runningCount) running")
                .foregroundStyle(.primary)
            Text("·").foregroundStyle(.tertiary)
            Text("\(entry.data.needsYouCount) waiting")
                .foregroundStyle(entry.data.needsYouCount > 0 ? Color.orange : Color.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// "Morning briefing · Commander"; nil when no automation is scheduled.
    private var nextAutomationText: String? {
        guard let name = entry.data.nextAutomationName else { return nil }
        guard let agent = entry.data.nextAutomationAgent, !agent.isEmpty else { return "Next: \(name)" }
        return "Next: \(name) · \(agent)"
    }

    // MARK: - Accessory Circular (Lock Screen)

    private var circularView: some View {
        VStack(spacing: 2) {
            HermesBrandIcon(size: 18)
            Circle()
                .fill(entry.data.hostOnline ? .green : .gray)
                .frame(width: 5, height: 5)
        }
        .widgetURL(URL(string: "hermes://chat"))
    }

    // MARK: - Accessory Rectangular (Lock Screen)

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                HermesBrandIcon(size: 14)
                Text("Hermes")
                    .font(.headline)
                Spacer()
            }

            boardCounts
                .font(.caption)

            if let automation = nextAutomationText {
                Text(automation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(entry.data.hostOnline ? "Ready" : "Offline")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .widgetURL(URL(string: "hermes://chat"))
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    HermesStatusWidget()
} timeline: {
    HermesWidgetEntry.placeholder
    HermesWidgetEntry(date: .now, data: .empty)
}

#Preview("Circular", as: .accessoryCircular) {
    HermesStatusWidget()
} timeline: {
    HermesWidgetEntry.placeholder
}

#Preview("Rectangular", as: .accessoryRectangular) {
    HermesStatusWidget()
} timeline: {
    HermesWidgetEntry.placeholder
}
