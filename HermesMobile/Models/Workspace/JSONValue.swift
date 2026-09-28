import Foundation

/// Any JSON value, for loosely typed payloads such as kanban event details.
enum JSONValue: Decodable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

/// Decodes and discards any payload; for endpoints whose response we don't use.
struct IgnoredResponse: Decodable, Sendable {
    init() {}
    init(from decoder: Decoder) throws {}
}

enum HermesDate {
    /// Parses Hermes ISO-8601 strings, including microsecond precision and offsets.
    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = RelayCoders.parseRelayDate(value) { return date }
        // Trim sub-millisecond digits ("…35.226303+00:00" -> "…35.226+00:00").
        let trimmed = value.replacingOccurrences(
            of: #"(\.\d{3})\d+"#,
            with: "$1",
            options: .regularExpression
        )
        return RelayCoders.parseRelayDate(trimmed)
    }

    static func fromUnix(_ value: Double?) -> Date? {
        value.map { Date(timeIntervalSince1970: $0) }
    }
}
