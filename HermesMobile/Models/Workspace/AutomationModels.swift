import Foundation

struct CronSchedule: Decodable, Hashable, Sendable {
    var kind: String?
    var expr: String?
    var display: String?
}

struct CronJob: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var prompt: String
    var schedule: CronSchedule?
    var scheduleDisplay: String?
    var enabled: Bool
    var state: String?
    var nextRunAtRaw: String?
    var lastRunAtRaw: String?
    var lastStatus: String?
    var lastError: String?
    var deliver: String?
    var profile: String?

    enum CodingKeys: String, CodingKey {
        case id, name, prompt, schedule, enabled, state, deliver, profile
        case scheduleDisplay = "schedule_display"
        case nextRunAtRaw = "next_run_at"
        case lastRunAtRaw = "last_run_at"
        case lastStatus = "last_status"
        case lastError = "last_error"
    }

    var isPaused: Bool { state == "paused" || !enabled }
    var nextRunAt: Date? { HermesDate.parse(nextRunAtRaw) }
    var lastRunAt: Date? { HermesDate.parse(lastRunAtRaw) }

    /// A readable schedule: "daily at 08:00" style text when Hermes provides it.
    var scheduleText: String {
        let raw = schedule?.display ?? scheduleDisplay ?? schedule?.expr ?? ""
        return CronSchedulePreset.describe(expression: raw) ?? raw
    }

    var displayName: String { name.isEmpty ? String(prompt.prefix(40)) : name }
}

struct CronRun: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String?
    var preview: String?
    var endReason: String?
    var startedAtUnix: Double?
    var endedAtUnix: Double?
    var estimatedCostUSD: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, preview
        case endReason = "end_reason"
        case startedAtUnix = "started_at"
        case endedAtUnix = "ended_at"
        case estimatedCostUSD = "estimated_cost_usd"
    }

    var startedAt: Date? { HermesDate.fromUnix(startedAtUnix) }
    var succeeded: Bool { endReason == nil || endReason == "cron_complete" || endReason == "agent_close" }
}

struct CronRunsResponse: Decodable, Sendable {
    var runs: [CronRun]
}

struct SessionMessage: Decodable, Identifiable, Sendable {
    var id: Int
    var role: String
    var content: String?
}

struct SessionMessagesResponse: Decodable, Sendable {
    var messages: [SessionMessage]

    /// The final assistant reply, which is a cron run's output.
    var finalReply: String? {
        messages.last { $0.role == "assistant" && !($0.content ?? "").isEmpty }?.content
    }
}

struct CronBlueprintField: Decodable, Hashable, Sendable {
    var name: String
    var type: String
    var label: String
    var defaultValue: String?
    var options: [String]
    var optional: Bool
    var help: String?

    enum CodingKeys: String, CodingKey {
        case name, type, label, options, optional, help
        case defaultValue = "default"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        label = try container.decode(String.self, forKey: .label)
        defaultValue = try? container.decodeIfPresent(String.self, forKey: .defaultValue)
        options = (try? container.decodeIfPresent([String].self, forKey: .options)) ?? []
        optional = (try? container.decodeIfPresent(Bool.self, forKey: .optional)) ?? false
        help = try? container.decodeIfPresent(String.self, forKey: .help)
    }

    var isChoice: Bool { type == "enum" || type == "weekdays" }
    /// Delivery targets are hidden: results are read in the app, so jobs deliver locally.
    var isDelivery: Bool { name == "deliver" }
}

struct CronBlueprint: Decodable, Identifiable, Hashable, Sendable {
    var key: String
    var title: String
    var description: String
    var category: String
    var fields: [CronBlueprintField]
    var scheduleHuman: String?

    var id: String { key }

    var symbol: String {
        switch category {
        case "daily": "sun.horizon"
        case "weekly": "calendar"
        case "email": "envelope"
        default:
            switch key {
            case "price-watch": "tag"
            case "news-digest": "newspaper"
            case "competitor-watch": "binoculars"
            case "custom-reminder": "bell"
            default: "sparkles"
            }
        }
    }
}

struct CronBlueprintsResponse: Decodable, Sendable {
    var blueprints: [CronBlueprint]
}

struct CronJobDraft: Encodable, Equatable, Sendable {
    var name: String
    var prompt: String
    var schedule: String
    var deliver: String = "local"
    var paused: Bool = false
}

struct CronJobUpdate: Encodable, Sendable {
    var updates: [String: String]
}

struct BlueprintInstantiation: Encodable, Sendable {
    var blueprint: String
    var values: [String: String]
}

/// Friendly schedule choices that compile to cron expressions.
enum CronSchedulePreset: Hashable, Sendable {
    case everyMorning(hour: Int, minute: Int)
    case hourly
    case weekdays(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)
    case custom(String)

    var expression: String {
        switch self {
        case .everyMorning(let hour, let minute): "\(minute) \(hour) * * *"
        case .hourly: "0 * * * *"
        case .weekdays(let hour, let minute): "\(minute) \(hour) * * 1-5"
        case .weekly(let weekday, let hour, let minute): "\(minute) \(hour) * * \(weekday)"
        case .custom(let expression): expression.trimmingCharacters(in: .whitespaces)
        }
    }

    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// Human text for the common expressions this app creates; nil otherwise.
    static func describe(expression: String) -> String? {
        let parts = expression.split(separator: " ").map(String.init)
        guard parts.count == 5, let minute = Int(parts[0]) else {
            return expression == "0 * * * *" ? "Every hour" : nil
        }
        if parts[1] == "*" && parts[2] == "*" && parts[3] == "*" && parts[4] == "*" {
            return minute == 0 ? "Every hour" : "Every hour at :\(String(format: "%02d", minute))"
        }
        guard let hour = Int(parts[1]), parts[2] == "*", parts[3] == "*" else { return nil }
        let time = String(format: "%02d:%02d", hour, minute)
        switch parts[4] {
        case "*": return "Every day at \(time)"
        case "1-5": return "Weekdays at \(time)"
        case "0,6", "6,0": return "Weekends at \(time)"
        default:
            if let day = Int(parts[4]), (0 ... 6).contains(day) {
                return "\(weekdayNames[day])s at \(time)"
            }
            return nil
        }
    }
}
