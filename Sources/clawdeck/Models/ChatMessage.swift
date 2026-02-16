import Foundation
import AppKit

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

/// An image attached to a message (for display in chat bubbles).
struct MessageImage: Identifiable {
    let id = UUID()
    let image: NSImage
    let mimeType: String
    let fileName: String?
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

    /// Image attachments sent with this message.
    var images: [MessageImage] = []

    /// Tool calls made during this assistant response (in order of invocation).
    var toolCalls: [ToolCall] = []

    /// Tracks where the current streaming segment starts within `content`.
    /// Used by MessageStore to detect new segments vs cumulative growth.
    var segmentOffset: Int = 0

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

        // Extract text content and tool calls
        let textContent: String
        var historyToolCalls: [ToolCall] = []
        if let content = raw["content"] as? String {
            // Plain string content
            textContent = content
        } else if let contentBlocks = raw["content"] as? [[String: Any]] {
            // Array of content blocks — extract text blocks and tool calls
            let textParts = contentBlocks.compactMap { block -> String? in
                guard let type = block["type"] as? String else { return nil }
                switch type {
                case "text":
                    let text = block["text"] as? String
                    if text == nil {
                        AppLogger.warning("History text block has nil text at index \(index)", category: "Protocol")
                    }
                    return text
                case "thinking":
                    return nil  // Skip thinking blocks
                case "toolCall":
                    // Extract tool call info for visualization
                    let toolCallId = block["id"] as? String ?? block["toolCallId"] as? String ?? UUID().uuidString
                    let toolName = block["toolName"] as? String ?? block["name"] as? String ?? "tool"
                    let args = block["args"] as? [String: Any] ?? block["input"] as? [String: Any]
                    let toolCall = ToolCall(
                        id: toolCallId,
                        name: toolName,
                        phase: .completed,
                        args: args
                    )
                    historyToolCalls.append(toolCall)
                    return nil
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

        let message = ChatMessage(
            id: "history-\(index)",
            role: messageRole,
            content: textContent,
            timestamp: timestamp,
            sessionKey: sessionKey,
            state: .complete,
            model: model
        )
        message.toolCalls = historyToolCalls
        return message
    }
}
