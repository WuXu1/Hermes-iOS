import SwiftUI

extension KanbanStatus {
    var color: Color {
        switch self {
        case .running: Design.Colors.success
        case .blocked: Design.Colors.warning
        case .review: Color(hex: 0x64D2FF)
        case .ready, .todo, .triage, .scheduled: Design.Colors.textSecondary
        case .done, .archived, .unknown: Design.Colors.textTertiary
        }
    }

    var symbol: String {
        switch self {
        case .running: "bolt.fill"
        case .blocked: "hand.raised.fill"
        case .review: "eye.fill"
        case .ready: "tray.full.fill"
        case .todo: "hourglass"
        case .scheduled: "calendar"
        case .triage: "tray"
        case .done: "checkmark"
        case .archived: "archivebox"
        case .unknown: "questionmark"
        }
    }

    var pill: StatusPill {
        StatusPill(label: label, color: color, systemImage: symbol)
    }
}

/// Navigation value for a task's detail screen.
struct TaskRoute: Hashable {
    let id: String
}
