import SwiftUI

/// What a fresh chat shows: a greeting, the team's status, and starters for
/// the things people most often ask Hermes to do.
struct ChatEmptyState: View {
    let onStarter: (String) -> Void

    @Environment(TeamStore.self) private var teamStore
    @Environment(TabRouter.self) private var router

    private struct Starter: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let subtitle: String
        let template: String
    }

    private let starters = [
        Starter(id: "research", symbol: "magnifyingglass", title: "Research", subtitle: "Sourced answers from the web", template: "Research "),
        Starter(id: "web", symbol: "safari", title: "Do it on the web", subtitle: "Lookups, forms, account chores", template: "Go to "),
        Starter(id: "automate", symbol: "clock.arrow.2.circlepath", title: "Automate", subtitle: "Run something on a schedule", template: "Every morning at 8, "),
        Starter(id: "remember", symbol: "brain", title: "Remember", subtitle: "Teach Hermes about you", template: "Remember that "),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                    Text(greeting)
                        .font(.largeTitle.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(Design.Colors.textPrimary)
                    Text("What should Hermes take care of?")
                        .font(.title3)
                        .foregroundStyle(Design.Colors.textSecondary)
                }
                .padding(.top, Design.Spacing.xl)

                if teamStore.workingCount > 0 || teamStore.needsYouCount > 0 {
                    teamStrip
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Design.Spacing.sm) {
                    ForEach(starters) { starter in
                        Button { onStarter(starter.template) } label: {
                            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                                Image(systemName: starter.symbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Design.Brand.accent)
                                Spacer(minLength: Design.Spacing.xs)
                                Text(starter.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Design.Colors.textPrimary)
                                Text(starter.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(Design.Colors.textTertiary)
                                    .lineLimit(2)
                            }
                            .padding(Design.Spacing.md)
                            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
                            .cardSurface()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("chat.starter.\(starter.id)")
                    }
                }

                Button {
                    router.presentSheet(.newTask(prefill: nil))
                } label: {
                    Label("Give the team a task", systemImage: "person.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Design.Brand.accent)
                }
                .padding(.top, Design.Spacing.xxs)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.bottom, Design.Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var teamStrip: some View {
        Button {
            router.selectedTab = .team
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                HStack(spacing: -8) {
                    ForEach(activeRoles.prefix(4), id: \.self) { name in
                        RoleAvatar(style: RoleStyle.forProfile(name), size: .small)
                            .background(Circle().fill(Design.Colors.canvas))
                    }
                }
                Text(teamSummary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Design.Colors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Design.Colors.textTertiary)
            }
            .padding(Design.Spacing.sm)
            .cardSurface(cornerRadius: Design.CornerRadius.md)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Team tab")
    }

    private var activeRoles: [String] {
        var seen: [String] = []
        for task in teamStore.board.allTasks where task.status == .running || task.status == .blocked {
            if let name = task.assignee, !seen.contains(name) { seen.append(name) }
        }
        return seen
    }

    private var teamSummary: String {
        var parts: [String] = []
        if teamStore.workingCount > 0 { parts.append("\(teamStore.workingCount) working") }
        if teamStore.needsYouCount > 0 { parts.append("\(teamStore.needsYouCount) need\(teamStore.needsYouCount == 1 ? "s" : "") you") }
        return parts.joined(separator: " · ")
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5 ..< 12: "Good morning"
        case 12 ..< 17: "Good afternoon"
        case 17 ..< 22: "Good evening"
        default: "Hello"
        }
    }
}
