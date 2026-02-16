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

    /// Tracks the character count of the last delta per runId.
    /// Within a segment, delta length monotonically increases (cumulative).
    /// A shorter delta definitively signals a new segment started.
    private var lastDeltaLength: [String: Int] = [:]

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
                // (e.g. after tool calls).
                //
                // Detection: within a segment, each cumulative delta is strictly
                // longer than the previous. A shorter delta means a new segment.
                // This is more reliable than the previous hasPrefix heuristic,
                // which could false-positive when a new segment starts with the
                // same characters as the current one.
                let prevLength = lastDeltaLength[runId] ?? 0

                if !newContent.isEmpty && newContent.count < prevLength {
                    // New segment — delta is shorter than the last one, meaning
                    // the gateway reset for a new text block (after a tool call).
                    AppLogger.debug("New segment for runId=\(runId): delta \(newContent.count) < prev \(prevLength)", category: "Protocol")
                    if !existing.content.isEmpty {
                        existing.content += "\n\n"
                    }
                    existing.segmentOffset = existing.content.count
                    existing.content += newContent
                    lastDeltaLength[runId] = newContent.count
                } else {
                    // Same segment growing (or equal) — replace from segment offset.
                    // Guard: only apply if the resulting content is at least as long
                    // as what we already have, preventing accidental truncation.
                    let candidate = String(existing.content.prefix(existing.segmentOffset)) + newContent
                    if candidate.count >= existing.content.count {
                        existing.content = candidate
                        lastDeltaLength[runId] = newContent.count
                    } else {
                        AppLogger.debug("Stale delta skipped for runId=\(runId): candidate \(candidate.count) < existing \(existing.content.count)", category: "Protocol")
                    }
                }
                streamingContentVersion += 1
            } else {
                // First delta for this run — create streaming message
                AppLogger.debug("Streaming started for runId=\(runId) sessionKey=\(sessionKey) length=\(newContent.count)", category: "Protocol")
                let message = ChatMessage.streamPlaceholder(
                    runId: runId,
                    sessionKey: sessionKey,
                    agentId: event.message?.agentId
                )
                message.content = newContent
                message.segmentOffset = 0
                lastDeltaLength[runId] = newContent.count
                streamingMessages[runId] = message
                allMessagesBySession[sessionKey, default: []].append(message)
                // Expand visible window so streaming message is visible
                let currentVisible = visibleCountBySession[sessionKey] ?? Self.initialPageSize
                visibleCountBySession[sessionKey] = currentVisible + 1
            }

        case "final":
            if let existing = streamingMessages[runId] {
                // Finalize the streaming message.
                //
                // The final event's content may only contain the *last* text
                // segment (after the last tool call), not the full accumulated
                // response. We must never let it shrink what we already have
                // from streaming deltas — that causes visible truncation.
                if let content = event.message?.content, !content.isEmpty {
                    if existing.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        AppLogger.debug("Final for runId=\(runId): no delta content, using final (\(content.count) chars)", category: "Protocol")
                        existing.content = content
                    } else if content.count > existing.content.count {
                        AppLogger.debug("Final for runId=\(runId): final longer (\(content.count) > \(existing.content.count)), using final", category: "Protocol")
                        existing.content = content
                    } else {
                        AppLogger.debug("Final for runId=\(runId): keeping accumulated (\(existing.content.count) chars, final was \(content.count))", category: "Protocol")
                    }
                } else {
                    AppLogger.debug("Final for runId=\(runId): no final content, keeping accumulated (\(existing.content.count) chars)", category: "Protocol")
                }
                existing.state = .complete
                streamingMessages.removeValue(forKey: runId)
                lastDeltaLength.removeValue(forKey: runId)
            } else {
                // Final without prior deltas — create complete message
                let contentLength = event.message?.content?.count ?? 0
                AppLogger.debug("Final without prior deltas for runId=\(runId): \(contentLength) chars", category: "Protocol")
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
                AppLogger.warning("Streaming error for runId=\(runId): \(event.errorMessage ?? "unknown"), accumulated \(existing.content.count) chars", category: "Protocol")
                existing.state = .error
                existing.errorMessage = event.errorMessage ?? "Unknown error"
                streamingMessages.removeValue(forKey: runId)
                lastDeltaLength.removeValue(forKey: runId)
            }

        default:
            break
        }
    }

    /// Check if a session has an active streaming message.
    func isStreaming(sessionKey: String) -> Bool {
        streamingMessages.values.contains { $0.sessionKey == sessionKey }
    }

    /// Finalize all active streaming messages for a session (e.g. after abort).
    /// Marks them as complete so the UI stops showing the typing indicator.
    func finalizeStreaming(for sessionKey: String) {
        let keys = streamingMessages.filter { $0.value.sessionKey == sessionKey }.map(\.key)
        for key in keys {
            streamingMessages[key]?.state = .complete
            streamingMessages.removeValue(forKey: key)
            lastDeltaLength.removeValue(forKey: key)
        }
    }

    /// Finalize all active streaming messages across all sessions.
    /// Called when the gateway connection drops to prevent orphaned typing indicators.
    func finalizeAllStreaming() {
        guard !streamingMessages.isEmpty else { return }
        AppLogger.warning("Finalizing \(streamingMessages.count) orphaned streaming message(s) due to connection loss", category: "Protocol")
        for (_, message) in streamingMessages {
            message.state = .complete
        }
        streamingMessages.removeAll()
        lastDeltaLength.removeAll()
    }

    // MARK: - Cleanup

    /// Remove all messages for a session.
    func clearSession(_ sessionKey: String) {
        allMessagesBySession.removeValue(forKey: sessionKey)
        visibleCountBySession.removeValue(forKey: sessionKey)
        let keysToRemove = streamingMessages.filter { $0.value.sessionKey == sessionKey }.map(\.key)
        for key in keysToRemove {
            streamingMessages.removeValue(forKey: key)
            lastDeltaLength.removeValue(forKey: key)
        }
    }

    /// Remove all messages.
    func clearAll() {
        allMessagesBySession.removeAll()
        visibleCountBySession.removeAll()
        streamingMessages.removeAll()
        lastDeltaLength.removeAll()
    }
}
