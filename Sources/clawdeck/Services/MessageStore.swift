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

    /// Tracks which text segment index we're currently streaming into per runId.
    private var currentTextSegmentIndex: [String: Int] = [:]

    /// Tracks the character count of the last thinking delta per runId.
    private var lastThinkingDeltaLength: [String: Int] = [:]

    /// Tracks which thinking segment index we're currently streaming into per runId.
    private var currentThinkingSegmentIndex: [String: Int] = [:]

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
            let newThinking = event.message?.thinkingContent

            if let existing = streamingMessages[runId] {
                // Handle thinking content
                if let thinking = newThinking, !thinking.isEmpty {
                    let prevThinkingLength = lastThinkingDeltaLength[runId] ?? 0

                    if thinking.count < prevThinkingLength {
                        // New thinking segment
                        existing.segments.append(.thinking(id: "think-\(existing.segments.count)", content: thinking))
                        currentThinkingSegmentIndex[runId] = existing.segments.count - 1
                    } else if let segIdx = currentThinkingSegmentIndex[runId], segIdx < existing.segments.count {
                        // Update current thinking segment
                        existing.segments[segIdx] = .thinking(id: existing.segments[segIdx].id, content: thinking)
                    } else {
                        // First thinking segment
                        existing.segments.append(.thinking(id: "think-\(existing.segments.count)", content: thinking))
                        currentThinkingSegmentIndex[runId] = existing.segments.count - 1
                    }
                    lastThinkingDeltaLength[runId] = thinking.count
                }

                // Handle text content
                let prevLength = lastDeltaLength[runId] ?? 0

                if !newContent.isEmpty && newContent.count < prevLength {
                    // New segment — delta is shorter than the last one, meaning
                    // the gateway reset for a new text block (after a tool call).
                    AppLogger.debug("New segment for runId=\(runId): delta \(newContent.count) < prev \(prevLength)", category: "Protocol")

                    // Legacy content tracking
                    if !existing.content.isEmpty {
                        existing.content += "\n\n"
                    }
                    existing.segmentOffset = existing.content.count
                    existing.content += newContent

                    // Segments: start a new text segment
                    existing.segments.append(.text(id: "seg-\(existing.segments.count)", content: newContent))
                    currentTextSegmentIndex[runId] = existing.segments.count - 1

                    lastDeltaLength[runId] = newContent.count
                } else if !newContent.isEmpty {
                    // Same segment growing — replace from segment offset.
                    let candidate = String(existing.content.prefix(existing.segmentOffset)) + newContent
                    if candidate.count >= existing.content.count {
                        existing.content = candidate

                        // Update the current text segment
                        if let segIdx = currentTextSegmentIndex[runId], segIdx < existing.segments.count {
                            existing.segments[segIdx] = .text(id: existing.segments[segIdx].id, content: newContent)
                        } else {
                            // No segment yet — create first one
                            if existing.segments.isEmpty || !existing.segments.last!.isText {
                                existing.segments.append(.text(id: "seg-\(existing.segments.count)", content: newContent))
                                currentTextSegmentIndex[runId] = existing.segments.count - 1
                            }
                        }

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

                // Initialize segments — thinking first if present, then text
                var initialSegments: [MessageSegment] = []

                if let thinking = newThinking, !thinking.isEmpty {
                    initialSegments.append(.thinking(id: "think-0", content: thinking))
                    currentThinkingSegmentIndex[runId] = 0
                    lastThinkingDeltaLength[runId] = thinking.count
                }

                if !newContent.isEmpty {
                    initialSegments.append(.text(id: "seg-\(initialSegments.count)", content: newContent))
                    currentTextSegmentIndex[runId] = initialSegments.count - 1
                }

                if initialSegments.isEmpty {
                    initialSegments.append(.text(id: "seg-0", content: newContent))
                    currentTextSegmentIndex[runId] = 0
                }

                message.segments = initialSegments

                lastDeltaLength[runId] = newContent.count
                streamingMessages[runId] = message
                allMessagesBySession[sessionKey, default: []].append(message)
                let currentVisible = visibleCountBySession[sessionKey] ?? Self.initialPageSize
                visibleCountBySession[sessionKey] = currentVisible + 1
            }

        case "final":
            // Extract usage from the final event
            let parsedUsage = Self.parseUsage(from: event.usage)

            if let existing = streamingMessages[runId] {
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
                existing.usage = parsedUsage
                streamingMessages.removeValue(forKey: runId)
                lastDeltaLength.removeValue(forKey: runId)
                currentTextSegmentIndex.removeValue(forKey: runId)
                lastThinkingDeltaLength.removeValue(forKey: runId)
                currentThinkingSegmentIndex.removeValue(forKey: runId)
            } else {
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
                message.usage = parsedUsage
                allMessagesBySession[sessionKey, default: []].append(message)
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
                currentTextSegmentIndex.removeValue(forKey: runId)
                lastThinkingDeltaLength.removeValue(forKey: runId)
                currentThinkingSegmentIndex.removeValue(forKey: runId)
            }

        default:
            break
        }
    }

    /// Check if a session has an active streaming message.
    func isStreaming(sessionKey: String) -> Bool {
        streamingMessages.values.contains { $0.sessionKey == sessionKey }
    }

    /// Patch usage data onto a completed message identified by runId.
    /// Used to backfill usage from history after streaming completes.
    func patchUsage(for sessionKey: String, runId: String, usage: MessageUsage) {
        guard let messages = allMessagesBySession[sessionKey] else { return }
        // Search from the end — the target message is usually the most recent.
        for message in messages.reversed() {
            if message.runId == runId && message.role == .assistant {
                message.usage = usage
                return
            }
        }
    }

    /// Finalize all active streaming messages for a session (e.g. after abort).
    func finalizeStreaming(for sessionKey: String) {
        let keys = streamingMessages.filter { $0.value.sessionKey == sessionKey }.map(\.key)
        for key in keys {
            streamingMessages[key]?.state = .complete
            streamingMessages.removeValue(forKey: key)
            lastDeltaLength.removeValue(forKey: key)
            currentTextSegmentIndex.removeValue(forKey: key)
            lastThinkingDeltaLength.removeValue(forKey: key)
            currentThinkingSegmentIndex.removeValue(forKey: key)
        }
    }

    /// Finalize all active streaming messages across all sessions.
    func finalizeAllStreaming() {
        guard !streamingMessages.isEmpty else { return }
        AppLogger.warning("Finalizing \(streamingMessages.count) orphaned streaming message(s) due to connection loss", category: "Protocol")
        for (_, message) in streamingMessages {
            message.state = .complete
        }
        streamingMessages.removeAll()
        lastDeltaLength.removeAll()
        currentTextSegmentIndex.removeAll()
        lastThinkingDeltaLength.removeAll()
        currentThinkingSegmentIndex.removeAll()
    }

    // MARK: - Tool calls

    /// Handle a tool call event from the agent stream.
    func handleToolEvent(runId: String, sessionKey: String, phase: String, toolCallId: String, toolName: String, args: [String: Any]?, result: String?, isError: Bool) {
        let message = streamingMessages[runId]
            ?? allMessagesBySession[sessionKey]?.last(where: { $0.role == .assistant && $0.runId == runId })

        guard let message else {
            AppLogger.debug("Tool event for unknown runId=\(runId), creating placeholder", category: "Protocol")
            let placeholder = ChatMessage.streamPlaceholder(runId: runId, sessionKey: sessionKey)
            streamingMessages[runId] = placeholder
            allMessagesBySession[sessionKey, default: []].append(placeholder)
            let currentVisible = visibleCountBySession[sessionKey] ?? Self.initialPageSize
            visibleCountBySession[sessionKey] = currentVisible + 1
            handleToolEvent(runId: runId, sessionKey: sessionKey, phase: phase, toolCallId: toolCallId, toolName: toolName, args: args, result: result, isError: isError)
            return
        }

        switch phase {
        case "start":
            let toolCall = ToolCall(id: toolCallId, name: toolName, args: args)
            // Append to segments — this inserts tool calls between text segments
            message.appendToolCall(toolCall)
            // Clear the text segment index so next text delta creates a new segment
            currentTextSegmentIndex.removeValue(forKey: runId)
            AppLogger.debug("Tool start: \(toolName) (\(toolCallId)) for runId=\(runId)", category: "Protocol")

        case "update":
            if let existing = message.findToolCall(id: toolCallId) {
                existing.result = result
            }

        case "result":
            if let existing = message.findToolCall(id: toolCallId) {
                existing.result = result
                existing.isError = isError
                existing.phase = isError ? .error : .completed
                AppLogger.debug("Tool \(isError ? "error" : "result"): \(toolName) (\(toolCallId))", category: "Protocol")
            }

        default:
            break
        }

        streamingContentVersion += 1
    }

    // MARK: - Usage parsing

    /// Parse usage data from a ChatEventPayload's usage field.
    private static func parseUsage(from usageAnyCodable: AnyCodable?) -> MessageUsage? {
        guard let usageDict = usageAnyCodable?.dictValue else { return nil }

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

        guard usage.totalTokens > 0 else { return nil }
        return usage
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
            currentTextSegmentIndex.removeValue(forKey: key)
            lastThinkingDeltaLength.removeValue(forKey: key)
            currentThinkingSegmentIndex.removeValue(forKey: key)
        }
    }

    /// Remove all messages.
    func clearAll() {
        allMessagesBySession.removeAll()
        visibleCountBySession.removeAll()
        streamingMessages.removeAll()
        lastDeltaLength.removeAll()
        currentTextSegmentIndex.removeAll()
        lastThinkingDeltaLength.removeAll()
        currentThinkingSegmentIndex.removeAll()
    }
}
