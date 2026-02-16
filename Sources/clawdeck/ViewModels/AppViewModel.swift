import AppKit
import Foundation
import SwiftUI

/// Root application state that owns all services and top-level data.
@Observable
@MainActor
final class AppViewModel {
    // MARK: - Services

    let gatewayManager = GatewayManager()
    let messageStore = MessageStore()

    // MARK: - Child View Models (created once, shared)

    /// Sidebar view model — owned here so it survives re-renders.
    private(set) var sidebarViewModel: SidebarViewModel!

    /// Cached chat view models keyed by session key — prevents draft text
    /// loss on re-renders.
    private var chatViewModels: [String: ChatViewModel] = [:]

    /// In-flight history load task — cancelled when selecting a different session.
    private var historyLoadTask: Task<Void, Never>?

    /// Session key for the in-flight history load.
    /// Prevents re-entering selectSession from cancelling a load for
    /// the same session that's already in progress.
    private var historyLoadingKey: String?

    /// Get or create a ChatViewModel for a session key.
    func chatViewModel(for sessionKey: String) -> ChatViewModel {
        if let existing = chatViewModels[sessionKey] {
            return existing
        }
        let vm = ChatViewModel(sessionKey: sessionKey, appViewModel: self)
        chatViewModels[sessionKey] = vm
        return vm
    }

    // MARK: - State

    /// Currently selected agent binding in the rail.
    var activeBinding: AgentBinding?

    /// All known agents from all connected gateways.
    var agents: [Agent] = []

    /// All sessions from the active gateway (unfiltered cache).
    private var allGatewaySessions: [Session] = []

    /// Sessions visible in the sidebar (filtered to the active agent).
    var sessions: [Session] = []

    /// Currently selected session key.
    var selectedSessionKey: String?

    /// Whether the inspector panel is visible.
    var isInspectorVisible = false

    /// Whether the sidebar is collapsed.
    var isSidebarCollapsed = false

    /// Trigger to focus the composer text field. Incremented to signal focus.
    var focusComposerTrigger: Int = 0

    /// Trigger to focus the search bar. Incremented to signal focus.
    var focusSearchBarTrigger: Int = 0

    /// Whether the onboarding/connection setup is shown.
    var showConnectionSetup = false

    /// Whether the agent settings sheet is shown.
    var showAgentSettings = false

    /// Whether the "connect new gateway" sheet is shown (from + popover).
    var showGatewayConnectionSheet = false

    /// Cached list of available models from the active gateway.
    var availableModels: [GatewayModel] = []

    /// The agent-level default model ID (from SessionsListResult.defaults.model).
    var defaultModelId: String?

    /// The agent-level default model provider (from SessionsListResult.defaults.modelProvider).
    var defaultModelProvider: String?

    /// Custom accent color set from Agent Settings. Applied app-wide.
    var customAccentColor: Color?

    /// Profile ID being edited (nil = adding new, non-nil = editing).
    var editingAgentProfileId: String?

    /// Currently selected session.
    var selectedSession: Session? {
        sessions.first { $0.key == selectedSessionKey }
    }

    /// Whether the app has any configured gateway profiles.
    var hasProfiles: Bool {
        !gatewayManager.gatewayProfiles.isEmpty
    }

    /// Shortcut to the client for the active binding's gateway.
    var activeClient: GatewayClient? {
        guard let binding = activeBinding else { return nil }
        return gatewayManager.client(for: binding.gatewayId)
    }

    // MARK: - Init

    init() {
        sidebarViewModel = SidebarViewModel(appViewModel: self)

        // Wire up event handling
        gatewayManager.onEvent = { [weak self] event, gatewayId in
            Task { @MainActor in
                self?.handleEvent(event, gatewayId: gatewayId)
            }
        }

        // Wire up connection state change handling
        gatewayManager.onConnectionStateChange = { [weak self] newState, gatewayId in
            Task { @MainActor in
                self?.handleConnectionStateChange(newState, gatewayId: gatewayId)
            }
        }

        // Load persisted accent color
        loadAccentColor()

        // Show setup on first launch
        if !hasProfiles {
            showConnectionSetup = true
        }
    }

    // MARK: - Connection

    /// Connect to all gateways and load initial data.
    func connectAndLoad() async {
        await gatewayManager.connectAll()

        // Set active binding before loading data — loadInitialData() needs
        // activeClient (which depends on activeBinding) to fetch models.
        if activeBinding == nil, let firstBinding = gatewayManager.sortedAgentBindings.first {
            activeBinding = firstBinding
        }

        await loadInitialData()
    }

    /// Switch to a different agent binding.
    func switchAgent(_ binding: AgentBinding) async {
        let previousGatewayId = activeBinding?.gatewayId
        activeBinding = binding
        
        if previousGatewayId != binding.gatewayId {
            // Different gateway — reload sessions and models from the new gateway
            allGatewaySessions.removeAll()
            await refreshSessions()
            await fetchModels()
        } else {
            // Same gateway — just filter the cached sessions (instant)
            filterSessionsToActiveAgent()
        }
    }

    /// Disconnect from all gateways.
    func disconnect() {
        gatewayManager.disconnectAll()
        activeBinding = nil
        agents.removeAll()
        allGatewaySessions.removeAll()
        sessions.removeAll()
        selectedSessionKey = nil
        availableModels.removeAll()
        defaultModelId = nil
        defaultModelProvider = nil
        messageStore.clearAll()
        chatViewModels.removeAll()
    }

    // MARK: - Data loading

    /// Load agents and sessions after connecting.
    func loadInitialData() async {
        AppLogger.info("Loading initial data...", category: "Session")
        await refreshAgents()
        await refreshSessions()
        await fetchModels()
        AppLogger.info("Loaded \(agents.count) agents, \(sessions.count) sessions, \(availableModels.count) models", category: "Session")
    }

    /// Refresh agents from all connected gateways.
    func refreshAgents() async {
        var allAgents: [Agent] = []
        
        for (gatewayId, agentSummaries) in gatewayManager.agentSummaries {
            let gatewayAgents = agentSummaries.map { Agent(from: $0) }
            allAgents.append(contentsOf: gatewayAgents)
        }
        
        agents = allAgents
        AppLogger.info("Loaded \(agents.count) agents from \(gatewayManager.agentSummaries.count) gateways", category: "Session")
    }

    /// Refresh sessions from the active binding's gateway.
    func refreshSessions() async {
        guard let binding = activeBinding,
              let client = gatewayManager.client(for: binding.gatewayId) else {
            allGatewaySessions.removeAll()
            sessions.removeAll()
            return
        }
        
        do {
            let result = try await client.listSessions()
            AppLogger.debug("sessions.list returned \(result.sessions.count) sessions for gateway \(binding.gatewayId)", category: "Session")

            // Build a lookup of existing createdAt values so we don't lose them on refresh.
            let existingCreatedAt = Dictionary(uniqueKeysWithValues:
                allGatewaySessions.map { ($0.key, $0.createdAt) }
            )

            // Store default model info from the gateway response
            defaultModelId = result.defaults?.model
            defaultModelProvider = result.defaults?.modelProvider

            allGatewaySessions = result.sessions
                .sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
                .map { summary in
                    let session = Session.from(summary: summary)
                    // Preserve the original createdAt if we've seen this session before.
                    if let existing = existingCreatedAt[session.key] {
                        session.createdAt = existing
                    }
                    return session
                }
            
            // Filter to the active agent
            filterSessionsToActiveAgent()
        } catch {
            AppLogger.error("Failed to list sessions: \(error)", category: "Session")
        }
    }

    /// Filter cached sessions to the active agent (for same-gateway switches).
    private func filterSessionsToActiveAgent() {
        guard let binding = activeBinding else {
            sessions.removeAll()
            return
        }
        
        sessions = allGatewaySessions.filter { session in
            session.agentId == binding.agentId
        }
        
        // Clear selection if the selected session doesn't belong to this agent
        if let selectedKey = selectedSessionKey,
           !sessions.contains(where: { $0.key == selectedKey }) {
            selectedSessionKey = nil
        }
    }

    // MARK: - Models

    /// Fetch available models from the active gateway and cache them.
    func fetchModels() async {
        guard let client = activeClient else {
            availableModels = []
            return
        }
        do {
            let result = try await client.modelsList()
            availableModels = result.models
            AppLogger.info("Fetched \(result.models.count) models from gateway", category: "Session")
        } catch {
            AppLogger.error("Failed to fetch models: \(error)", category: "Session")
            // Keep any previously cached models
        }
    }

    /// Set a model override for a session. Pass `nil` to reset to default.
    ///
    /// Sends `sessions.patch` with the model (or "default" to reset),
    /// then updates the local session object.
    func setSessionModel(_ modelId: String?, for sessionKey: String) async {
        guard let client = activeClient else { return }
        let patchModel = modelId ?? "default"
        do {
            try await client.patchSession(key: sessionKey, model: patchModel)
            // Update the local session with the bare model ID and provider
            if let session = sessions.first(where: { $0.key == sessionKey }) {
                if let modelId {
                    // modelId may be "provider/id" — split to store separately
                    let parts = modelId.split(separator: "/", maxSplits: 1)
                    if parts.count == 2 {
                        session.modelProvider = String(parts[0])
                        session.model = String(parts[1])
                    } else {
                        session.model = modelId
                        session.modelProvider = availableModels.first(where: { $0.id == modelId })?.provider
                    }
                } else {
                    session.model = nil
                    session.modelProvider = nil
                }
            }
            AppLogger.info("Set model for \(sessionKey): \(patchModel)", category: "Session")
        } catch {
            AppLogger.error("Failed to set model for \(sessionKey): \(error)", category: "Session")
        }
    }

    // MARK: - Session actions

    /// Select a session and load its history.
    func selectSession(_ sessionKey: String) async {
        selectedSessionKey = sessionKey

        // Already have messages — nothing to load.
        guard !messageStore.hasMessages(for: sessionKey) else {
            AppLogger.debug("selectSession(\(sessionKey)): already has messages, skipping", category: "Session")
            return
        }

        // Already loading this exact session — don't cancel and restart.
        guard historyLoadingKey != sessionKey else {
            AppLogger.debug("selectSession(\(sessionKey)): already loading, skipping", category: "Session")
            return
        }

        // Cancel any in-flight load for a *different* session.
        if let previousKey = historyLoadingKey {
            AppLogger.debug("selectSession(\(sessionKey)): cancelling load for \(previousKey)", category: "Session")
        }
        historyLoadTask?.cancel()
        historyLoadingKey = sessionKey

        AppLogger.debug("selectSession(\(sessionKey)): starting history load", category: "Session")
        let task = Task { await loadHistory(for: sessionKey) }
        historyLoadTask = task
        await task.value

        // Clear the loading key if it still matches (wasn't replaced).
        if historyLoadingKey == sessionKey {
            historyLoadingKey = nil
        }
    }

    /// Maximum number of messages to request in chat.history.
    /// The gateway has a per-connection send buffer limit (~1.5 MB). Large sessions
    /// with many tool calls can exceed this, causing the connection to drop.
    /// Start with a moderate limit; on connection-lost errors, retry with fewer.
    private static let historyLimits = [200, 100, 50, 25]

    /// Load chat history for a session, retrying with smaller limits if the
    /// response is too large for the gateway's send buffer.
    func loadHistory(for sessionKey: String) async {
        guard activeClient != nil else { return }
        guard !Task.isCancelled else { return }

        for limit in Self.historyLimits {
            guard !Task.isCancelled else { return }
            let success = await loadHistoryAttempt(for: sessionKey, limit: limit)
            if success { return }

            // If we got here, the load failed (likely connection dropped).
            // Wait for actual reconnection before retrying with a smaller limit.
            AppLogger.warning("History load failed with limit=\(limit), waiting for reconnection...", category: "Session")
            let reconnected = await waitForReconnection(timeout: 15)
            guard reconnected else {
                AppLogger.error("Reconnection timed out for \(sessionKey)", category: "Session")
                return
            }
            AppLogger.info("Reconnected, retrying with smaller limit...", category: "Session")
        }
        AppLogger.error("All history load attempts failed for \(sessionKey)", category: "Session")
    }

    /// Whether the active binding's gateway is connected.
    private var isActiveGatewayConnected: Bool {
        guard let binding = activeBinding else { return false }
        return gatewayManager.isConnected(binding.gatewayId)
    }

    /// Wait until the connection is re-established or timeout expires.
    /// Returns true if connected, false if timed out or cancelled.
    private func waitForReconnection(timeout: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while Date() < deadline {
            guard !Task.isCancelled else { return false }
            if isActiveGatewayConnected { return true }
            try? await Task.sleep(nanoseconds: 500_000_000) // poll every 0.5s
        }
        return isActiveGatewayConnected
    }

    /// Single attempt to load history with a specific limit. Returns true on success.
    private func loadHistoryAttempt(for sessionKey: String, limit: Int) async -> Bool {
        guard let client = activeClient else { return false }
        guard !Task.isCancelled else { return false }
        do {
            let response = try await client.send(
                method: GatewayMethod.chatHistory,
                params: ChatHistoryParams(sessionKey: sessionKey, limit: limit)
            )

            // After the await, check if this load is still relevant.
            // The user may have switched sessions while we waited.
            guard !Task.isCancelled else { return false }

            guard response.ok, let payload = response.payload else {
                AppLogger.error("chat.history failed: \(response.error?.message ?? "unknown")", category: "Session")
                return false
            }

            // Decode payload as raw dictionary to handle complex content field
            let payloadData = try JSONSerialization.data(withJSONObject: payload.value as Any)
            let payloadDict = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
            let rawMessages = payloadDict?["messages"] as? [[String: Any]] ?? []

            AppLogger.debug("chat.history returned \(rawMessages.count) raw messages for \(sessionKey) (limit=\(limit))", category: "Session")

            let allParsed = rawMessages.enumerated().compactMap { index, raw in
                ChatMessage.fromHistory(raw, sessionKey: sessionKey, index: index)
            }

            // Match tool results back to their tool calls.
            // The gateway stores: assistant (with toolCall blocks) → toolResult → assistant (next text).
            // We enrich the assistant's ToolCall objects with the result content.
            Self.enrichToolCallsWithResults(allParsed, rawMessages: rawMessages)

            let allMessages = allParsed.filter { $0.isVisible }

            // Merge consecutive assistant messages into a single message.
            // The gateway stores separate messages for each text segment
            // around tool calls, but the user sees them as one reply.
            let messages = Self.mergeConsecutiveAssistantMessages(allMessages)

            AppLogger.debug("\(allMessages.count) visible → \(messages.count) after merging consecutive assistant messages", category: "Session")
            messageStore.setMessages(messages, for: sessionKey)
            return true
        } catch is CancellationError {
            // Expected when the user switches sessions before the load completes.
            AppLogger.debug("History load cancelled (task cancellation) for \(sessionKey)", category: "Session")
            return false
        } catch GatewayClientError.cancelled {
            // Thrown when the WebSocket disconnects and all pending requests
            // are flushed (e.g. reconnection). Not a user-initiated cancel.
            AppLogger.warning("History load interrupted (connection lost, limit=\(limit)) for \(sessionKey)", category: "Session")
            return false
        } catch {
            AppLogger.error("Failed to load history for \(sessionKey): \(type(of: error)) — \(error.localizedDescription)", category: "Session")
            return false
        }
    }

    /// Delete a session.
    func deleteSession(_ sessionKey: String) async {
        guard let client = activeClient else { return }
        do {
            try await client.deleteSession(key: sessionKey)
            sessions.removeAll { $0.key == sessionKey }
            messageStore.clearSession(sessionKey)
            if selectedSessionKey == sessionKey {
                selectedSessionKey = sessions.first?.key
            }
        } catch {
            // Handle error
        }
    }

    /// Rename a session.
    func renameSession(_ sessionKey: String, label: String) async {
        guard let client = activeClient else { return }
        do {
            try await client.patchSession(key: sessionKey, label: label)
            if let session = sessions.first(where: { $0.key == sessionKey }) {
                session.label = label
            }
            AppLogger.info("Renamed session \(sessionKey) to '\(label)'", category: "Session")
        } catch {
            AppLogger.error("Failed to rename session: \(error)", category: "Session")
        }
    }

    // MARK: - New session

    /// Create a new session by generating a unique key and selecting it.
    /// The session is created on the gateway implicitly when the first message is sent.
    func createNewSession() async {
        guard let binding = activeBinding else { return }
        
        let shortId = UUID().uuidString.prefix(8).lowercased()
        let sessionKey = "agent:\(binding.agentId):\(shortId)"

        let newSession = Session(
            key: sessionKey,
            agentId: binding.agentId,
            updatedAt: Date(),
            isActive: true
        )
        sessions.insert(newSession, at: 0)
        selectedSessionKey = sessionKey
        AppLogger.info("Created new session: \(sessionKey)", category: "Session")
    }

    // MARK: - Accent Color

    /// Apply a custom accent color app-wide via NSAppearance.
    func applyAccentColor(_ color: Color) {
        customAccentColor = color
        // Persist to UserDefaults as hex
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let hex = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        UserDefaults.standard.set(hex, forKey: "com.clawdbot.deck.accentColor")
    }

    /// Load saved accent color from UserDefaults.
    func loadAccentColor() {
        guard let hex = UserDefaults.standard.string(forKey: "com.clawdbot.deck.accentColor"),
              !hex.isEmpty else { return }
        let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard clean.count == 6,
              let r = Int(clean.prefix(2), radix: 16),
              let g = Int(clean.dropFirst(2).prefix(2), radix: 16),
              let b = Int(clean.suffix(2), radix: 16) else { return }
        customAccentColor = Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    // MARK: - Event handling

    private func handleEvent(_ event: EventFrame, gatewayId: String) {
        switch event.event {
        case GatewayEvent.chat:
            handleChatEvent(event, gatewayId: gatewayId)

        case GatewayEvent.agent:
            handleAgentEvent(event, gatewayId: gatewayId)

        case GatewayEvent.presence:
            handlePresenceEvent(event)

        case GatewayEvent.shutdown:
            // Gateway shutting down — will auto-reconnect
            break

        case GatewayEvent.tick:
            // Keepalive — nothing to do
            break

        default:
            break
        }
    }

    private func handleConnectionStateChange(_ newState: ConnectionState, gatewayId: String) {
        // Only act on the active gateway's state changes
        guard let binding = activeBinding, binding.gatewayId == gatewayId else { return }

        switch newState {
        case .disconnected, .reconnecting:
            // Finalize orphaned streaming messages to clear typing indicators
            AppLogger.info("Active gateway \(gatewayId) \(newState.rawValue), finalizing streams", category: "Network")
            messageStore.finalizeAllStreaming()
            // Reset send/await state on all active ChatViewModels
            for (_, vm) in chatViewModels {
                vm.isSending = false
                vm.isAwaitingResponse = false
            }
        case .connecting, .connected:
            break
        }
    }

    private func handleChatEvent(_ event: EventFrame, gatewayId: String) {
        // Only handle events from the active gateway
        guard let activeBinding = activeBinding,
              activeBinding.gatewayId == gatewayId else {
            return
        }
        
        guard let payload = event.payload else {
            AppLogger.warning("chat event has no payload", category: "Protocol")
            return
        }
        do {
            let chatEvent = try payload.decode(ChatEventPayload.self)
            AppLogger.debug("chat event: state=\(chatEvent.state) runId=\(chatEvent.runId) sessionKey=\(chatEvent.sessionKey) content=\(chatEvent.message?.content?.prefix(80) ?? "nil")", category: "Protocol")
            messageStore.handleChatEvent(chatEvent)

            // Update session's last message preview (but don't change updatedAt
            // to avoid re-sorting the sidebar and disrupting the user's selection).
            if chatEvent.state == "final", let content = chatEvent.message?.content {
                if let session = sessions.first(where: { $0.key == chatEvent.sessionKey }) {
                    session.lastMessage = String(content.prefix(100))
                    session.lastMessageAt = Date()
                    // Note: updatedAt is intentionally NOT updated here.
                    // Session order refreshes on next full sessions.list call,
                    // not on every streaming event. This prevents the sidebar
                    // from re-sorting under the user and stealing selection.
                }
            }
        } catch {
            AppLogger.error("Failed to decode chat event: \(error)", category: "Protocol")
            // Log the raw payload for debugging
            if let dict = payload.dictValue {
                AppLogger.debug("Raw payload keys: \(dict.keys.sorted())", category: "Protocol")
                if let msg = dict["message"] as? [String: Any] {
                    AppLogger.debug("message keys: \(msg.keys.sorted())", category: "Protocol")
                    AppLogger.debug("content type: \(type(of: msg["content"] as Any))", category: "Protocol")
                }
            }
        }
    }

    private func handleAgentEvent(_ event: EventFrame, gatewayId: String) {
        // Only handle events from the active gateway
        guard let activeBinding = activeBinding,
              activeBinding.gatewayId == gatewayId else { return }

        guard let payload = event.payload?.dictValue else { return }

        let stream = payload["stream"] as? String
        guard stream == "tool" else { return }  // Only handle tool stream events

        guard let data = payload["data"] as? [String: Any],
              let phase = data["phase"] as? String,
              let toolCallId = data["toolCallId"] as? String else { return }

        let runId = payload["runId"] as? String ?? ""
        let sessionKey = payload["sessionKey"] as? String ?? ""
        let toolName = data["name"] as? String ?? "tool"

        // Extract args (start phase) or result (result phase)
        let args = data["args"] as? [String: Any]
        let resultValue = data["result"]
        let resultText: String?
        if let resultStr = resultValue as? String {
            resultText = resultStr
        } else if let resultDict = resultValue as? [String: Any] {
            // Try to get a compact JSON representation
            if let jsonData = try? JSONSerialization.data(withJSONObject: resultDict, options: [.fragmentsAllowed]),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                resultText = String(jsonStr.prefix(2000))
            } else {
                resultText = String(describing: resultDict).prefix(2000).description
            }
        } else if resultValue != nil {
            resultText = String(describing: resultValue!).prefix(2000).description
        } else {
            resultText = nil
        }

        let isError = data["isError"] as? Bool ?? false

        messageStore.handleToolEvent(
            runId: runId,
            sessionKey: sessionKey,
            phase: phase,
            toolCallId: toolCallId,
            toolName: toolName,
            args: args,
            result: resultText,
            isError: isError
        )
    }

    private func handlePresenceEvent(_ event: EventFrame) {
        guard let payload = event.payload else { return }
        do {
            let presence = try payload.decode(PresencePayload.self)
            if let agentId = presence.agentId,
               let agent = agents.first(where: { $0.id == agentId }) {
                agent.isOnline = (presence.status == "online")
            }
        } catch {
            // Failed to decode presence
        }
    }
    // MARK: - Keyboard Shortcut Actions

    /// Toggle sidebar collapsed state.
    func toggleSidebar() {
        isSidebarCollapsed.toggle()
    }

    /// Focus the composer text field.
    func focusComposer() {
        focusComposerTrigger += 1
    }

    /// Focus the search bar (Quick Open).
    func focusSearchBar() {
        focusSearchBarTrigger += 1
    }

    /// Close/deselect the current session.
    func closeCurrentSession() {
        selectedSessionKey = nil
    }

    /// Navigate to the previous session in the sidebar list.
    func selectPreviousSession() {
        let sessionList = sidebarViewModel.filteredSessions
        guard !sessionList.isEmpty else { return }

        if let currentKey = selectedSessionKey,
           let currentIndex = sessionList.firstIndex(where: { $0.key == currentKey }) {
            let previousIndex = currentIndex - 1
            if previousIndex >= 0 {
                Task { await selectSession(sessionList[previousIndex].key) }
            }
        } else {
            // No session selected — select the last one
            Task { await selectSession(sessionList.last!.key) }
        }
    }

    /// Navigate to the next session in the sidebar list.
    func selectNextSession() {
        let sessionList = sidebarViewModel.filteredSessions
        guard !sessionList.isEmpty else { return }

        if let currentKey = selectedSessionKey,
           let currentIndex = sessionList.firstIndex(where: { $0.key == currentKey }) {
            let nextIndex = currentIndex + 1
            if nextIndex < sessionList.count {
                Task { await selectSession(sessionList[nextIndex].key) }
            }
        } else {
            // No session selected — select the first one
            Task { await selectSession(sessionList.first!.key) }
        }
    }

    /// Switch to an agent by its 1-based index in the rail.
    func switchToAgent(at index: Int) {
        let bindings = gatewayManager.sortedAgentBindings
        guard index >= 1, index <= bindings.count else { return }
        let binding = bindings[index - 1]
        Task { await switchAgent(binding) }
    }

    // MARK: - Message merging

    /// Merge consecutive assistant messages into single messages.
    ///
    /// The gateway transcript stores a separate message for each text segment
    /// around tool-call / tool-result pairs. When loaded as history these
    /// appear as multiple small bubbles for what was a single assistant turn.
    /// This method joins them so the UI shows one cohesive reply that can be
    /// selected and copied as a whole.
    /// Match tool result messages to their corresponding tool calls.
    /// The gateway transcript follows the pattern:
    ///   assistant (content: [text, toolCall, toolCall, ...])
    ///   toolResult (for each tool call)
    ///   assistant (next text segment)
    static func enrichToolCallsWithResults(_ messages: [ChatMessage], rawMessages: [[String: Any]]) {
        // Build a lookup of tool call IDs to ToolCall objects
        var toolCallLookup: [String: ToolCall] = [:]
        for message in messages where message.role == .assistant {
            for tc in message.toolCalls {
                toolCallLookup[tc.id] = tc
            }
        }

        guard !toolCallLookup.isEmpty else { return }

        // Scan raw messages for toolResult entries and match them
        for raw in rawMessages {
            guard let role = raw["role"] as? String, role == "toolResult" else { continue }

            // Try to find the tool call ID this result belongs to
            let toolCallId = raw["toolCallId"] as? String ?? raw["tool_call_id"] as? String

            // Extract the result content
            let resultText: String?
            if let content = raw["content"] as? String {
                resultText = content
            } else if let contentBlocks = raw["content"] as? [[String: Any]] {
                let texts = contentBlocks.compactMap { block -> String? in
                    guard let type = block["type"] as? String, type == "text" else { return nil }
                    return block["text"] as? String
                }
                resultText = texts.joined(separator: "\n")
            } else {
                resultText = nil
            }

            let isError = raw["isError"] as? Bool ?? false

            if let id = toolCallId, let toolCall = toolCallLookup[id] {
                toolCall.result = resultText.map { String($0.prefix(2000)) }
                toolCall.isError = isError
                toolCall.phase = isError ? .error : .completed
            }
        }
    }

    static func mergeConsecutiveAssistantMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        guard !messages.isEmpty else { return [] }

        var merged: [ChatMessage] = []

        for message in messages {
            if message.role == .assistant,
               let last = merged.last,
               last.role == .assistant {
                // Merge segments, but deduplicate text segments.
                // The gateway may repeat the same text in each assistant
                // continuation turn during multi-step tool use.
                let existingTexts = Set(last.segments.compactMap(\.textContent))
                let existingThinking = Set(last.segments.compactMap(\.thinkingContent))

                for segment in message.segments {
                    if case .text(_, let content) = segment {
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty || existingTexts.contains(content) {
                            continue  // Skip duplicate or empty text
                        }
                    }
                    if case .thinking(_, let content) = segment {
                        if existingThinking.contains(content) {
                            continue  // Skip duplicate thinking
                        }
                    }
                    last.segments.append(segment)
                }

                // Rebuild content from merged segments
                last.syncContentFromSegments()
            } else {
                merged.append(message)
            }
        }

        return merged
    }
}
// Session.from(summary:) is defined in Session.swift
