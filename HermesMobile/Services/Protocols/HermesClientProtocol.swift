import Foundation

@MainActor
protocol HermesClientProtocol {
    var connectionStatus: ConnectionStatus { get }
    var currentConversation: Conversation? { get }
    func setActiveProfile(_ profile: String)
    func connect() async
    func disconnect() async
    func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message
    func sendStreaming(message: String, attachments: [PendingAttachment], clientMessageID: UUID) -> AsyncStream<StreamingUpdate>
    func loadConversation() async -> Conversation
    func clearConversation() async throws -> Conversation
    func transcribe(audio: Data, mimeType: String) async throws -> String
}

extension HermesClientProtocol {
    /// Clients without server transcription (test stubs) refuse it.
    func transcribe(audio: Data, mimeType: String) async throws -> String {
        throw NSError(domain: "Hermes", code: 1, userInfo: [NSLocalizedDescriptionKey: "Voice notes aren't available."])
    }
}
