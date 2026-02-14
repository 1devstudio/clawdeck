import Foundation

/// In-memory message store that manages chat messages per session.
@Observable
@MainActor
final class MessageStore {
    /// All messages indexed by session key (full history from gateway).
    private var allMessagesBySession: [String: [ChatMessage]] = [:]

    /// Number of messages currently visible per session (pagination window).
    /// Grows as the user scrolls up to load more.
    private var visibleCountBySession: [String: Int] = [:]

    /// Default number of messages to show initially.
    static let initialPageSize = 50

    /// Number of additional messages to load when scrolling up.
    static let pageSize = 50

    /// Active streaming messages by runId.
    private var streamingMessages: [String: ChatMessage] = [:]

    /// Incremented on every streaming delta — observe this to trigger auto-scroll.
    private(set) var streamingContentVersion: Int = 0

    // MARK: - Read

    /// Get the currently visible messages for a session (paginated tail).
    func messages(for sessionKey: String) -> [ChatMessage] {
        guard let all = allMessagesBySession[sessionKey] else { return [] }
        let visibleCount = visibleCountBySession[sessionKey] ?? Self.initialPageSize
        let startIndex = max(0, all.count - visibleCount)
        return Array(all[startIndex...])
    }

    /// Check if a session has any messages loaded.
    func hasMessages(for sessionKey: String) -> Bool {
        !(allMessagesBySession[sessionKey]?.isEmpty ?? true)
    }

    /// Whether there are older messages that can be loaded for this session.
    func hasMoreMessages(for sessionKey: String) -> Bool {
        guard let all = allMessagesBySession[sessionKey] else { return false }
        let visibleCount = visibleCountBySession[sessionKey] ?? Self.initialPageSize
        return visibleCount < all.count
    }

    /// Load the next page of older messages for a session.
    /// Returns the number of newly revealed messages.
    @discardableResult
    func loadMoreMessages(for sessionKey: String) -> Int {
        guard let all = allMessagesBySession[sessionKey] else { return 0 }
        let currentVisible = visibleCountBySession[sessionKey] ?? Self.initialPageSize
        let newVisible = min(currentVisible + Self.pageSize, all.count)
        let revealed = newVisible - currentVisible
        visibleCountBySession[sessionKey] = newVisible
        return revealed
    }

    // MARK: - Write

    /// Add a message to a session.
    func addMessage(_ message: ChatMessage) {
        allMessagesBySession[message.sessionKey, default: []].append(message)
        // Expand the visible window so new messages are always visible.
        let currentVisible = visibleCountBySession[message.sessionKey] ?? Self.initialPageSize
        visibleCountBySession[message.sessionKey] = currentVisible + 1
    }

    /// Set all messages for a session (e.g., from history).
    /// Shows the most recent `initialPageSize` messages.
    func setMessages(_ messages: [ChatMessage], for sessionKey: String) {
        allMessagesBySession[sessionKey] = messages
        visibleCountBySession[sessionKey] = min(Self.initialPageSize, messages.count)
    }

    /// Mark a user message as sent.
    func markSent(messageId: String, sessionKey: String) {
        guard let messages = allMessagesBySession[sessionKey],
              let index = messages.firstIndex(where: { $0.id == messageId })
        else { return }
        allMessagesBySession[sessionKey]?[index].state = .sent
    }

    /// Mark a user message as failed.
    func markError(messageId: String, sessionKey: String, error: String) {
        guard let messages = allMessagesBySession[sessionKey],
              let index = messages.firstIndex(where: { $0.id == messageId })
        else { return }
        allMessagesBySession[sessionKey]?[index].state = .error
        allMessagesBySession[sessionKey]?[index].errorMessage = error
    }

    // MARK: - Streaming

    /// Handle a chat event delta/final/error.
    func handleChatEvent(_ event: ChatEventPayload) {
        let sessionKey = event.sessionKey
        let runId = event.runId

        switch event.state {
        case "delta":
            let newContent = event.message?.content ?? ""

            if let existing = streamingMessages[runId] {
                // The gateway sends cumulative text within each text segment,
                // but resets to a short string when a new segment begins
                // (e.g. after tool calls). We detect this by checking if the
                // new content is a prefix of what we already have — if not,
                // a new segment started.
                let currentSegmentText = String(existing.content.suffix(from: existing.content.index(existing.content.startIndex, offsetBy: existing.segmentOffset)))

                if !newContent.isEmpty && !currentSegmentText.hasPrefix(newContent) && newContent.count < currentSegmentText.count {
                    // New segment — keep accumulated text + append new
                    if !existing.content.isEmpty {
                        existing.content += "\n\n"
                    }
                    existing.segmentOffset = existing.content.count
                    existing.content += newContent
                } else {
                    // Same segment growing — replace from segment offset
                    let prefix = String(existing.content.prefix(existing.segmentOffset))
                    existing.content = prefix + newContent
                }
                streamingContentVersion += 1
            } else {
                // First delta for this run — create streaming message
                let message = ChatMessage.streamPlaceholder(
                    runId: runId,
                    sessionKey: sessionKey,
                    agentId: event.message?.agentId
                )
                message.content = newContent
                message.segmentOffset = 0
                streamingMessages[runId] = message
                allMessagesBySession[sessionKey, default: []].append(message)
                // Expand visible window so streaming message is visible
                let currentVisible = visibleCountBySession[sessionKey] ?? Self.initialPageSize
                visibleCountBySession[sessionKey] = currentVisible + 1
            }

        case "final":
            if let existing = streamingMessages[runId] {
                // Finalize the streaming message.
                if let content = event.message?.content, !content.isEmpty {
                    let currentSegmentText = String(existing.content.suffix(from: existing.content.index(existing.content.startIndex, offsetBy: existing.segmentOffset)))

                    if existing.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // No delta content — use final directly
                        existing.content = content
                    } else if !currentSegmentText.hasPrefix(content) && content.count < currentSegmentText.count {
                        // Final is a new segment
                        existing.content += "\n\n" + content
                    } else {
                        // Final replaces current segment (complete version)
                        let prefix = String(existing.content.prefix(existing.segmentOffset))
                        existing.content = prefix + content
                    }
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
                allMessagesBySession[sessionKey, default: []].append(message)
                // Expand visible window
                let currentVisible = visibleCountBySession[sessionKey] ?? Self.initialPageSize
                visibleCountBySession[sessionKey] = currentVisible + 1
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
        allMessagesBySession.removeValue(forKey: sessionKey)
        visibleCountBySession.removeValue(forKey: sessionKey)
        streamingMessages = streamingMessages.filter { $0.value.sessionKey != sessionKey }
    }

    /// Remove all messages.
    func clearAll() {
        allMessagesBySession.removeAll()
        visibleCountBySession.removeAll()
        streamingMessages.removeAll()
    }
}
