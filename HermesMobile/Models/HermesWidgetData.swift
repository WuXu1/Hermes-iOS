import Foundation

/// Snapshot of app state shared between the main app and widget extension
/// via App Group UserDefaults. Updated by the main app whenever state changes;
/// read by widget timeline providers to render Home Screen widgets.
struct HermesWidgetData: Codable, Equatable, Sendable {
    var hostName: String?
    var hostOnline: Bool = false
    var lastMessagePreview: String?
    var lastMessageSender: String?   // "assistant", "user", "system"
    var lastMessageAt: Date?
    var steps: Int?
    var activeCalories: Int?
    var sleepHours: Double?
    var heartRate: Int?
    var runningCount: Int = 0
    var needsYouCount: Int = 0
    var nextAutomationName: String?
    var nextAutomationAgent: String?   // resolved display name of the agent the job runs as
    var nextAutomationAt: Date?
    var updatedAt: Date = .now

    static let empty = HermesWidgetData()
}
