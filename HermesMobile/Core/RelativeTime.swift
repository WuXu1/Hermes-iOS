import Foundation

enum RelativeTime {
    /// Compact past times: "just now", "6m ago", "3h ago", "2d ago", then a date.
    static func short(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 0 { return future(date, now: now) }
        switch seconds {
        case ..<45: return "just now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3600))h ago"
        case ..<(7 * 86_400): return "\(Int(seconds / 86_400))d ago"
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    /// Upcoming times: "in 12m", "in 3h", "tomorrow 08:00", or a date and time.
    static func future(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "" }
        let seconds = date.timeIntervalSince(now)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "in \(Int(seconds / 60))m" }
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDate(date, inSameDayAs: now) { return "today \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow \(time)"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// "12m", "1h 5m": how long something took.
    static func duration(from start: Date?, to end: Date?) -> String? {
        guard let start, let end else { return nil }
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
