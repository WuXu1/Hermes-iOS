import Foundation

enum KanbanStatus: String, CaseIterable, Sendable, Codable {
    case triage, todo, scheduled, ready, running, blocked, review, done, archived, unknown

    init(apiValue: String) {
        self = KanbanStatus(rawValue: apiValue) ?? .unknown
    }

    init(from decoder: Decoder) throws {
        self.init(apiValue: try decoder.singleValueContainer().decode(String.self))
    }

    var label: String {
        switch self {
        case .triage: "Triage"
        case .todo: "Waiting"
        case .scheduled: "Scheduled"
        case .ready: "Queued"
        case .running: "Working"
        case .blocked: "Needs you"
        case .review: "In review"
        case .done: "Done"
        case .archived: "Archived"
        case .unknown: "Unknown"
        }
    }

    var isOpen: Bool { self != .done && self != .archived }
}

struct KanbanTask: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var body: String?
    var assignee: String?
    var status: KanbanStatus
    var priority: Int?
    var createdBy: String?
    var createdAtUnix: Double?
    var startedAtUnix: Double?
    var completedAtUnix: Double?
    var latestSummary: String?
    var result: String?
    var lastFailureError: String?
    var blockKind: String?
    var sessionID: String?

    enum CodingKeys: String, CodingKey {
        case id, title, body, assignee, status, priority, result
        case createdBy = "created_by"
        case createdAtUnix = "created_at"
        case startedAtUnix = "started_at"
        case completedAtUnix = "completed_at"
        case latestSummary = "latest_summary"
        case lastFailureError = "last_failure_error"
        case blockKind = "block_kind"
        case sessionID = "session_id"
    }

    var createdAt: Date? { HermesDate.fromUnix(createdAtUnix) }
    var startedAt: Date? { HermesDate.fromUnix(startedAtUnix) }
    var completedAt: Date? { HermesDate.fromUnix(completedAtUnix) }

    /// The best one-line description of where the task stands.
    var headline: String? {
        let text = latestSummary ?? result ?? lastFailureError
        return text?
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

struct KanbanColumn: Decodable, Sendable {
    var name: String
    var tasks: [KanbanTask]
}

struct KanbanBoard: Decodable, Sendable {
    var columns: [KanbanColumn]

    var allTasks: [KanbanTask] { columns.flatMap(\.tasks) }

    static let empty = KanbanBoard(columns: [])
}

struct KanbanComment: Decodable, Identifiable, Hashable, Sendable {
    var id: Int
    var author: String?
    var body: String
    var createdAtUnix: Double?

    enum CodingKeys: String, CodingKey {
        case id, author, body
        case createdAtUnix = "created_at"
    }

    var createdAt: Date? { HermesDate.fromUnix(createdAtUnix) }
}

struct KanbanEvent: Decodable, Identifiable, Sendable {
    var id: Int
    var kind: String
    var payload: [String: JSONValue]?
    var createdAtUnix: Double?

    enum CodingKeys: String, CodingKey {
        case id, kind, payload
        case createdAtUnix = "created_at"
    }

    var createdAt: Date? { HermesDate.fromUnix(createdAtUnix) }
}

struct KanbanRun: Decodable, Identifiable, Sendable {
    var id: Int
    var profile: String?
    var status: String?
    var outcome: String?
    var summary: String?
    var error: String?
    var startedAtUnix: Double?
    var endedAtUnix: Double?

    enum CodingKeys: String, CodingKey {
        case id, profile, status, outcome, summary, error
        case startedAtUnix = "started_at"
        case endedAtUnix = "ended_at"
    }

    var startedAt: Date? { HermesDate.fromUnix(startedAtUnix) }
    var endedAt: Date? { HermesDate.fromUnix(endedAtUnix) }
}

struct KanbanAttachment: Decodable, Identifiable, Hashable, Sendable {
    var id: Int
    var filename: String
    var contentType: String?
    var size: Int?

    enum CodingKeys: String, CodingKey {
        case id, filename, size
        case contentType = "content_type"
    }

    var isText: Bool {
        if let contentType, contentType.hasPrefix("text/") || contentType == "application/json" { return true }
        let ext = (filename as NSString).pathExtension.lowercased()
        return ["md", "markdown", "txt", "json", "csv", "log", "py", "sh", "swift", "js", "ts", "yaml", "yml", "html"].contains(ext)
    }

    var isImage: Bool {
        if let contentType, contentType.hasPrefix("image/") { return true }
        return ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains((filename as NSString).pathExtension.lowercased())
    }
}

struct KanbanTaskDetail: Decodable, Sendable {
    var task: KanbanTask
    var comments: [KanbanComment]
    var events: [KanbanEvent]
    var attachments: [KanbanAttachment]
    var runs: [KanbanRun]

    enum CodingKeys: String, CodingKey {
        case task, comments, events, attachments, runs
    }

    init(task: KanbanTask, comments: [KanbanComment] = [], events: [KanbanEvent] = [], attachments: [KanbanAttachment] = [], runs: [KanbanRun] = []) {
        self.task = task
        self.comments = comments
        self.events = events
        self.attachments = attachments
        self.runs = runs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        task = try container.decode(KanbanTask.self, forKey: .task)
        comments = try container.decodeIfPresent([KanbanComment].self, forKey: .comments) ?? []
        events = try container.decodeIfPresent([KanbanEvent].self, forKey: .events) ?? []
        attachments = try container.decodeIfPresent([KanbanAttachment].self, forKey: .attachments) ?? []
        runs = try container.decodeIfPresent([KanbanRun].self, forKey: .runs) ?? []
    }
}

struct KanbanTaskLog: Decodable, Sendable {
    var exists: Bool
    var content: String
    var truncated: Bool
}

/// A file fetched through the proxy (kanban attachments).
struct HermesFilePayload: Decodable, Sendable {
    var contentType: String?
    var base64: String

    var data: Data? { Data(base64Encoded: base64) }
}

struct HermesProfile: Decodable, Identifiable, Hashable, Sendable {
    var name: String
    var isDefault: Bool
    var model: String?
    var provider: String?
    var description: String?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, model, provider, description
        case isDefault = "is_default"
    }
}

struct ProfilesResponse: Decodable, Sendable {
    var profiles: [HermesProfile]
}

struct TaskResponse: Decodable, Sendable {
    var task: KanbanTask
}

struct KanbanTaskDraft: Codable, Equatable, Sendable {
    var title: String
    var body: String?
    var assignee: String?
    var parents: [String] = []
}

struct KanbanTaskPatch: Encodable, Equatable, Sendable {
    var status: KanbanStatus?
    var summary: String?

    enum CodingKeys: String, CodingKey {
        case status, summary
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(status?.rawValue, forKey: .status)
        try container.encodeIfPresent(summary, forKey: .summary)
    }
}
