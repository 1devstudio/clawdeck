import Foundation

/// Role of a chat message sender.
enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

/// Lifecycle state of a chat message.
enum MessageState: String, Sendable {
    case sending     // User message in flight
    case sent        // User message acknowledged
    case streaming   // Assistant response being received
    case complete    // Final message
    case error       // Failed
}

/// A single message within a chat session.
@Observable
final class ChatMessage: Identifiable {
    let id: String
    let role: MessageRole
    var content: String
    let timestamp: Date
    let sessionKey: String
    var state: MessageState
    var agentId: String?
    var runId: String?
    var errorMessage: String?

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        sessionKey: String,
        state: MessageState = .complete,
        agentId: String? = nil,
        runId: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.sessionKey = sessionKey
        self.state = state
        self.agentId = agentId
        self.runId = runId
        self.errorMessage = errorMessage
    }
}

// MARK: - Convenience factories

extension ChatMessage {
    /// Create a user message about to be sent.
    static func outgoing(content: String, sessionKey: String) -> ChatMessage {
        ChatMessage(
            role: .user,
            content: content,
            sessionKey: sessionKey,
            state: .sending
        )
    }

    /// Create a placeholder for an incoming assistant stream.
    static func streamPlaceholder(
        runId: String,
        sessionKey: String,
        agentId: String? = nil
    ) -> ChatMessage {
        ChatMessage(
            role: .assistant,
            content: "",
            sessionKey: sessionKey,
            state: .streaming,
            agentId: agentId,
            runId: runId
        )
    }
}
