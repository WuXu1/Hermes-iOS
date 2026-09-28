import SwiftUI

// MARK: - Navigation Routes

enum Route: Hashable {
    case permissions
    case capture
    case connectHost
}

// MARK: - Sheet Destinations

enum SheetDestination: Identifiable {
    case settings
    case history
    case newTask(prefill: KanbanTaskDraft?)
    case newAutomation

    var id: String {
        switch self {
        case .settings: "settings"
        case .history: "history"
        case .newTask: "newTask"
        case .newAutomation: "newAutomation"
        }
    }
}

// MARK: - App Tab

enum AppTab: String, CaseIterable, Identifiable {
    case chat
    case team
    case automations
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: "Chat"
        case .team: "Team"
        case .automations: "Automations"
        case .library: "Library"
        }
    }

    var icon: String {
        switch self {
        case .chat: "bubble.left.and.text.bubble.right"
        case .team: "person.3"
        case .automations: "clock.arrow.2.circlepath"
        case .library: "books.vertical"
        }
    }
}

// MARK: - Router

@MainActor
@Observable
final class TabRouter {
    var selectedTab: AppTab = .chat
    var activeSheet: SheetDestination?
    var isVoiceOverlayPresented = false
    private var paths: [AppTab: NavigationPath] = [:]

    func pathBinding(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[tab] ?? NavigationPath() },
            set: { self.paths[tab] = $0 }
        )
    }

    /// The selected tab's path (kept for callers from before tabs existed).
    func pathBinding() -> Binding<NavigationPath> {
        pathBinding(for: selectedTab)
    }

    func navigate(to route: Route, in tab: AppTab? = nil) {
        push(route, in: tab)
    }

    /// Pushes any navigable value (a task, a job…) onto a tab's stack.
    func push(_ value: some Hashable, in tab: AppTab? = nil) {
        paths[tab ?? selectedTab, default: NavigationPath()].append(value)
    }

    /// Switches tab and shows `value` on top of that tab's root.
    func show(_ value: some Hashable, in tab: AppTab) {
        activeSheet = nil
        selectedTab = tab
        var path = NavigationPath()
        path.append(value)
        paths[tab] = path
    }

    func popToRoot(for tab: AppTab? = nil) {
        paths[tab ?? selectedTab] = NavigationPath()
    }

    func resetAll() {
        paths.removeAll()
    }

    func presentSheet(_ sheet: SheetDestination) {
        activeSheet = sheet
    }

    func dismissSheet() {
        activeSheet = nil
    }
}
