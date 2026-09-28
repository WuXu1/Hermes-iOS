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
    private var paths: [AppTab: [Route]] = [:]

    func path(for tab: AppTab? = nil) -> [Route] {
        paths[tab ?? selectedTab] ?? []
    }

    func pathBinding(for tab: AppTab) -> Binding<[Route]> {
        Binding(
            get: { self.paths[tab] ?? [] },
            set: { self.paths[tab] = $0 }
        )
    }

    /// The selected tab's path (kept for callers from before tabs existed).
    func pathBinding() -> Binding<[Route]> {
        pathBinding(for: selectedTab)
    }

    func binding(for tab: AppTab) -> Binding<[Route]> {
        pathBinding(for: tab)
    }

    func navigate(to route: Route, in tab: AppTab? = nil) {
        paths[tab ?? selectedTab, default: []].append(route)
    }

    func popToRoot(for tab: AppTab? = nil) {
        paths[tab ?? selectedTab] = []
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
