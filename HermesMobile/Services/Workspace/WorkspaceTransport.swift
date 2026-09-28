import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

enum WorkspaceError: LocalizedError, Equatable {
    case hostOffline
    case forbidden(String)
    case notFound(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .hostOffline: "Hermes is offline."
        case .forbidden(let message): message
        case .notFound(let message): message
        case .server(let message): message
        }
    }
}

/// Sends relay requests for the workspace screens (team, automations, library, history).
/// Paths are relay paths such as `hermes/api/plugins/kanban/board` or `conversations`.
@MainActor
protocol WorkspaceTransport: AnyObject {
    func send<Response: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String],
        body: (any Encodable)?
    ) async throws -> Response
}

extension WorkspaceTransport {
    func get<Response: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> Response {
        try await send(.get, path, query: query, body: nil)
    }

    /// For calls whose response body the app doesn't use.
    func perform(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String] = [:],
        body: (any Encodable)? = nil
    ) async throws {
        let _: IgnoredResponse = try await send(method, path, query: query, body: body)
    }
}

@MainActor
final class LiveWorkspaceTransport: WorkspaceTransport {
    private let apiClient: RelayAPIClient
    private let accessTokenProvider: @MainActor () async -> String?
    private let accessTokenRefresher: @MainActor () async -> String?

    init(
        apiClient: RelayAPIClient,
        accessTokenProvider: @escaping @MainActor () async -> String?,
        accessTokenRefresher: @escaping @MainActor () async -> String?
    ) {
        self.apiClient = apiClient
        self.accessTokenProvider = accessTokenProvider
        self.accessTokenRefresher = accessTokenRefresher
    }

    func send<Response: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        query: [String: String],
        body: (any Encodable)?
    ) async throws -> Response {
        do {
            do {
                return try await apiClient.request(
                    path: path,
                    method: method.rawValue,
                    query: query,
                    body: body,
                    accessToken: await accessTokenProvider()
                )
            } catch RelayAPIClient.ClientError.unauthorized {
                guard let refreshed = await accessTokenRefresher(), !refreshed.isEmpty else {
                    throw RelayAPIClient.ClientError.unauthorized("Expired or invalid access token.")
                }
                return try await apiClient.request(
                    path: path,
                    method: method.rawValue,
                    query: query,
                    body: body,
                    accessToken: refreshed
                )
            }
        } catch RelayAPIClient.ClientError.httpStatus(let status, let message) {
            throw Self.workspaceError(status: status, message: message)
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw WorkspaceError.server("No internet connection.")
        }
    }

    static func workspaceError(status: Int, message: String) -> WorkspaceError {
        switch status {
        case 409 where message.localizedCaseInsensitiveContains("offline") || message.localizedCaseInsensitiveContains("unavailable"):
            .hostOffline
        case 403:
            .forbidden(message)
        case 404:
            .notFound(message)
        default:
            .server(message)
        }
    }
}
