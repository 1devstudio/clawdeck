import Foundation

/// In-memory message store that manages chat messages per session.
@Observable
@MainActor
final class MessageStore {
    /// Messages indexed by session key.
    private var messagesBySession: [String: [ChatMessage]] = [:]

    /// Active streaming messages by runId.
    private var streamingMessages: [String: ChatMessage] = [:]

    /// Incremented on every streaming delta — observe this to trigger auto-scroll.
    private(set) var streamingContentVersion: Int = 0

    // MARK: - Read

    /// Get all messages for a session, ordered by timestamp.
    func messages(for sessionKey: String) -> [ChatMessage] {
        messagesBySession[sessionKey] ?? []
    }

    /// Check if a session has any messages loaded.
    func hasMessages(for sessionKey: String) -> Bool {
        !(messagesBySession[sessionKey]?.isEmpty ?? true)
    }

    // MARK: - Write

    /// Add a message to a session.
    func addMessage(_ message: ChatMessage) {
        messagesBySession[message.sessionKey, default: []].append(message)
    }

    /// Add multiple messages (e.g., from history).
    func setMessages(_ messages: [ChatMessage], for sessionKey: String) {
        messagesBySession[sessionKey] = messages
    }

    /// Mark a user message as sent.
    func markSent(messageId: String, sessionKey: String) {
        guard let messages = messagesBySession[sessionKey],
              let index = messages.firstIndex(where: { $0.id == messageId })
        else { return }
        messagesBySession[sessionKey]?[index].state = .sent
    }

    /// Mark a user message as failed.
    func markError(messageId: String, sessionKey: String, error: String) {
        guard let messages = messagesBySession[sessionKey],
              let index = messages.firstIndex(where: { $0.id == messageId })
        else { return }
        messagesBySession[sessionKey]?[index].state = .error
        messagesBySession[sessionKey]?[index].errorMessage = error
    }

    // MARK: - Streaming

    /// Handle a chat event delta/final/error.
    func handleChatEvent(_ event: ChatEventPayload) {
        let sessionKey = event.sessionKey
        let runId = event.runId

        switch event.state {
        case "delta":
            if let existing = streamingMessages[runId] {
                // Replace with latest cumulative content — the gateway sends
                // the full accumulated text in each delta, not incremental chunks.
                existing.content = event.message?.content ?? existing.content
                streamingContentVersion += 1
            } else {
                // Create new streaming message
                let message = ChatMessage.streamPlaceholder(
                    runId: runId,
                    sessionKey: sessionKey,
                    agentId: event.message?.agentId
                )
                message.content = event.message?.content ?? ""
                streamingMessages[runId] = message
                messagesBySession[sessionKey, default: []].append(message)
            }

        case "final":
            if let existing = streamingMessages[runId] {
                // Finalize the streaming message
                if let content = event.message?.content {
                    existing.content = content // Replace with final content
                }
                existing.state = .complete
                streamingMessages.removeValue(forKey: runId)
            } else {
                // Final without prior deltas — create complete message
                let message = ChatMessage(
                    role: .assistant,
                    content: event.message?.content ?? "",
                    sessionKey: sessionKey,
                    state: .complete,
                    agentId: event.message?.agentId,
                    runId: runId
                )
                messagesBySession[sessionKey, default: []].append(message)
            }

        case "error":
            if let existing = streamingMessages[runId] {
                existing.state = .error
                existing.errorMessage = event.errorMessage ?? "Unknown error"
                streamingMessages.removeValue(forKey: runId)
            }

        default:
            break
        }
    }

    /// Check if a session has an active streaming message.
    func isStreaming(sessionKey: String) -> Bool {
        streamingMessages.values.contains { $0.sessionKey == sessionKey }
    }

    // MARK: - Cleanup

    /// Remove all messages for a session.
    func clearSession(_ sessionKey: String) {
        messagesBySession.removeValue(forKey: sessionKey)
        streamingMessages = streamingMessages.filter { $0.value.sessionKey != sessionKey }
    }

    /// Remove all messages.
    func clearAll() {
        messagesBySession.removeAll()
        streamingMessages.removeAll()
    }
}
