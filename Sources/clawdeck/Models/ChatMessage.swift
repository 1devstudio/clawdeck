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

/// A segment of a message — either text content or a group of tool calls.
/// Messages are rendered as an ordered sequence of segments, preserving
/// the interleaving of text and tool calls as they actually occurred.
enum MessageSegment: Identifiable {
    case text(id: String, content: String)
    case toolGroup(id: String, toolCalls: [ToolCall])

    var id: String {
        switch self {
        case .text(let id, _): return id
        case .toolGroup(let id, _): return id
        }
    }

    var isText: Bool {
        if case .text = self { return true }
        return false
    }

    var textContent: String? {
        if case .text(_, let content) = self { return content }
        return nil
    }
}

/// Token usage and cost information for an assistant message.
struct MessageUsage {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0
    var totalTokens: Int = 0
    var cost: MessageCost?

    /// Compact token string (e.g. "17.2k" or "342")
    var formattedTotalTokens: String {
        if totalTokens >= 1_000_000 {
            return String(format: "%.1fM", Double(totalTokens) / 1_000_000)
        } else if totalTokens >= 1_000 {
            let k = Double(totalTokens) / 1_000
            return k >= 100 ? String(format: "%.0fk", k) : String(format: "%.1fk", k)
        }
        return "\(totalTokens)"
    }

    /// Compact cost string (e.g. "$0.01")
    var formattedTotalCost: String? {
        guard let total = cost?.total, total > 0 else { return nil }
        return total < 0.01 ? "<$0.01" : String(format: "$%.2f", total)
    }

    /// Compact summary (e.g. "17.2k tokens · $0.01")
    var compactSummary: String {
        var parts: [String] = []
        if totalTokens > 0 { parts.append("\(formattedTotalTokens) tokens") }
        if let costStr = formattedTotalCost { parts.append(costStr) }
        return parts.joined(separator: " · ")
    }
}

/// Cost breakdown for a message.
struct MessageCost {
    var input: Double = 0
    var output: Double = 0
    var cacheRead: Double = 0
    var cacheWrite: Double = 0
    var total: Double = 0
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

    /// Ordered segments — interleaved text and tool call groups.
    /// This is the primary data for rendering. `content` is kept in sync
    /// as the joined text (for search, copy, etc.)
    var segments: [MessageSegment] = []

    /// Token usage and cost information (for assistant messages).
    var usage: MessageUsage?

    /// Flat list of all tool calls (convenience accessor for search/merge).
    var toolCalls: [ToolCall] {
        segments.flatMap { segment in
            if case .toolGroup(_, let calls) = segment { return calls }
            return []
        }
    }

    /// Tracks where the current streaming segment starts within `content`.
    /// Used by MessageStore to detect new segments vs cumulative growth.
    var segmentOffset: Int = 0

    /// Whether this message should be displayed in the chat view.
    var isVisible: Bool {
        switch role {
        case .user, .assistant, .system:
            return !content.isEmpty || !segments.isEmpty
        case .toolResult, .toolCall:
            return false  // Hide tool interactions
        }
    }

    /// Whether this message has any segments to render (vs. just a plain content string).
    var hasSegments: Bool {
        !segments.isEmpty
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

    // MARK: - Segment helpers

    /// Append a tool call to the segments. If the last segment is already a tool group,
    /// add to it. Otherwise start a new tool group.
    func appendToolCall(_ toolCall: ToolCall) {
        if case .toolGroup(let groupId, var calls) = segments.last {
            calls.append(toolCall)
            segments[segments.count - 1] = .toolGroup(id: groupId, toolCalls: calls)
        } else {
            segments.append(.toolGroup(id: "tg-\(toolCall.id)", toolCalls: [toolCall]))
        }
    }

    /// Find a tool call by ID across all segments.
    func findToolCall(id: String) -> ToolCall? {
        for segment in segments {
            if case .toolGroup(_, let calls) = segment {
                if let tc = calls.first(where: { $0.id == id }) {
                    return tc
                }
            }
        }
        return nil
    }

    /// Ensure there's a text segment at the end (for streaming text after tool calls).
    func ensureTrailingTextSegment() {
        if case .text = segments.last {
            return  // Already have a trailing text segment
        }
        segments.append(.text(id: "seg-\(segments.count)", content: ""))
    }

    /// Update the last text segment's content.
    func updateLastTextSegment(_ text: String) {
        guard let lastIndex = segments.lastIndex(where: { $0.isText }) else {
            segments.append(.text(id: "seg-\(segments.count)", content: text))
            return
        }
        segments[lastIndex] = .text(id: segments[lastIndex].id, content: text)
    }

    /// Rebuild `content` from all text segments (for search, copy, etc.)
    func syncContentFromSegments() {
        let texts = segments.compactMap(\.textContent).filter { !$0.isEmpty }
        content = texts.joined(separator: "\n\n")
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
    /// We parse content blocks in order, building interleaved segments of text and tool calls.
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

        // Parse content blocks into ordered segments
        var segments: [MessageSegment] = []
        var allTextParts: [String] = []

        if let content = raw["content"] as? String {
            // Plain string content
            segments.append(.text(id: "seg-0", content: content))
            allTextParts.append(content)
        } else if let contentBlocks = raw["content"] as? [[String: Any]] {
            // Array of content blocks — preserve ordering
            var segIndex = 0
            var pendingToolCalls: [ToolCall] = []

            func flushToolCalls() {
                if !pendingToolCalls.isEmpty {
                    segments.append(.toolGroup(id: "tg-\(segIndex)", toolCalls: pendingToolCalls))
                    segIndex += 1
                    pendingToolCalls = []
                }
            }

            for block in contentBlocks {
                guard let type = block["type"] as? String else { continue }
                switch type {
                case "text":
                    guard let text = block["text"] as? String, !text.isEmpty else {
                        AppLogger.warning("History text block has nil/empty text at index \(index)", category: "Protocol")
                        continue
                    }
                    // Flush any pending tool calls before this text segment
                    flushToolCalls()
                    segments.append(.text(id: "seg-\(segIndex)", content: text))
                    segIndex += 1
                    allTextParts.append(text)

                case "toolCall", "tool_use":
                    let toolCallId = block["id"] as? String ?? block["toolCallId"] as? String ?? UUID().uuidString
                    let toolName = block["name"] as? String ?? block["toolName"] as? String ?? "tool"
                    let args = block["arguments"] as? [String: Any]
                        ?? block["args"] as? [String: Any]
                        ?? block["input"] as? [String: Any]
                    let toolCall = ToolCall(
                        id: toolCallId,
                        name: toolName,
                        phase: .completed,
                        args: args
                    )
                    pendingToolCalls.append(toolCall)

                case "thinking":
                    continue  // Skip thinking blocks

                default:
                    continue
                }
            }

            // Flush any trailing tool calls
            flushToolCalls()
        }

        let textContent = allTextParts.joined(separator: "\n\n")

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
        message.segments = segments

        // Parse usage data (for assistant messages)
        if messageRole == .assistant, let usageDict = raw["usage"] as? [String: Any] {
            var usage = MessageUsage()
            usage.inputTokens = usageDict["input"] as? Int ?? 0
            usage.outputTokens = usageDict["output"] as? Int ?? 0
            usage.cacheReadTokens = usageDict["cacheRead"] as? Int ?? 0
            usage.cacheWriteTokens = usageDict["cacheWrite"] as? Int ?? 0
            usage.totalTokens = usageDict["totalTokens"] as? Int
                ?? (usage.inputTokens + usage.outputTokens)

            if let costDict = usageDict["cost"] as? [String: Any] {
                var cost = MessageCost()
                cost.input = (costDict["input"] as? Double) ?? 0
                cost.output = (costDict["output"] as? Double) ?? 0
                cost.cacheRead = (costDict["cacheRead"] as? Double) ?? 0
                cost.cacheWrite = (costDict["cacheWrite"] as? Double) ?? 0
                cost.total = (costDict["total"] as? Double) ?? 0
                usage.cost = cost
            }

            message.usage = usage
        }

        return message
    }
}
