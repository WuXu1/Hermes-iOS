import Foundation

@MainActor
protocol HermesHostServiceProtocol {
    func fetchCurrentHost(accessToken: String?) async throws -> HermesHostStatus?
}
