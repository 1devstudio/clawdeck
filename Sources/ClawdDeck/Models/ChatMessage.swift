import Foundation

/// Role of a chat message sender.
enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
    case toolResult   // Tool call results — typically hidden in chat
    case toolCall     // Tool calls — typically hidden in chat
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
    var model: String?

    /// Whether this message should be displayed in the chat view.
    var isVisible: Bool {
        switch role {
        case .user, .assistant, .system:
            return !content.isEmpty
        case .toolResult, .toolCall:
            return false  // Hide tool interactions
        }
    }

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        sessionKey: String,
        state: MessageState = .complete,
        agentId: String? = nil,
        runId: String? = nil,
        errorMessage: String? = nil,
        model: String? = nil
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
        self.model = model
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

    /// Create a ChatMessage from a gateway history message.
    ///
    /// The gateway returns `content` as either:
    /// - A plain string (user messages sometimes)
    /// - An array of content blocks: `[{type: "text", text: "..."}, {type: "toolCall", ...}, ...]`
    ///
    /// We extract all `text` blocks and join them, skipping tool calls and tool results.
    static func fromHistory(_ raw: [String: Any], sessionKey: String, index: Int) -> ChatMessage? {
        guard let role = raw["role"] as? String else { return nil }

        // Map role
        let messageRole: MessageRole
        switch role {
        case "user": messageRole = .user
        case "assistant": messageRole = .assistant
        case "system": messageRole = .system
        case "toolResult": messageRole = .toolResult
        case "toolCall": messageRole = .toolCall
        default: return nil
        }

        // Extract text content
        let textContent: String
        if let content = raw["content"] as? String {
            // Plain string content
            textContent = content
        } else if let contentBlocks = raw["content"] as? [[String: Any]] {
            // Array of content blocks — extract text blocks
            let textParts = contentBlocks.compactMap { block -> String? in
                guard let type = block["type"] as? String else { return nil }
                switch type {
                case "text":
                    return block["text"] as? String
                case "thinking":
                    return nil  // Skip thinking blocks
                case "toolCall":
                    return nil  // Skip tool calls
                default:
                    return nil
                }
            }
            textContent = textParts.joined(separator: "\n\n")
        } else {
            textContent = ""
        }

        // Parse timestamp (epoch ms)
        let timestamp: Date
        if let ts = raw["timestamp"] as? Double {
            timestamp = Date(timeIntervalSince1970: ts / 1000.0)
        } else if let ts = raw["timestamp"] as? Int {
            timestamp = Date(timeIntervalSince1970: Double(ts) / 1000.0)
        } else {
            timestamp = Date()
        }

        let model = raw["model"] as? String

        return ChatMessage(
            id: "history-\(index)",
            role: messageRole,
            content: textContent,
            timestamp: timestamp,
            sessionKey: sessionKey,
            state: .complete,
            model: model
        )
    }
}
