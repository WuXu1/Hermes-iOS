import Foundation

struct HermesModelInfo: Decodable, Sendable {
    struct Capabilities: Decodable, Sendable {
        var supportsTools: Bool?
        var supportsVision: Bool?
        var supportsReasoning: Bool?

        enum CodingKeys: String, CodingKey {
            case supportsTools = "supports_tools"
            case supportsVision = "supports_vision"
            case supportsReasoning = "supports_reasoning"
        }
    }

    var model: String
    var provider: String?
    var effectiveContextLength: Int?
    var capabilities: Capabilities?

    enum CodingKeys: String, CodingKey {
        case model, provider, capabilities
        case effectiveContextLength = "effective_context_length"
    }
}

struct HermesUsage: Decodable, Sendable {
    struct Totals: Decodable, Sendable {
        var totalInput: Int
        var totalOutput: Int
        var totalEstimatedCost: Double
        var totalSessions: Int
        var totalAPICalls: Int

        enum CodingKeys: String, CodingKey {
            case totalInput = "total_input"
            case totalOutput = "total_output"
            case totalEstimatedCost = "total_estimated_cost"
            case totalSessions = "total_sessions"
            case totalAPICalls = "total_api_calls"
        }
    }

    var totals: Totals
    var periodDays: Int

    enum CodingKeys: String, CodingKey {
        case totals
        case periodDays = "period_days"
    }
}

struct HermesStatus: Decodable, Sendable {
    var version: String
    var gatewayRunning: Bool?
    var activeAgents: Int?
    var profiles: [String]?

    enum CodingKeys: String, CodingKey {
        case version, profiles
        case gatewayRunning = "gateway_running"
        case activeAgents = "active_agents"
    }
}
