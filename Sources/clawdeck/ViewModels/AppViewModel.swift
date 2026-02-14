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

    /// Whether the onboarding/connection setup is shown.
    var showConnectionSetup = false

    /// Whether the agent settings sheet is shown.
    var showAgentSettings = false

    /// Whether the "connect new gateway" sheet is shown (from + popover).
    var showGatewayConnectionSheet = false

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

        // Show setup on first launch
        if !hasProfiles {
            showConnectionSetup = true
        }
    }

    // MARK: - Connection

    /// Connect to all gateways and load initial data.
    func connectAndLoad() async {
        await gatewayManager.connectAll()
        await loadInitialData()
        
        // Set active binding to the first one if none is selected
        if activeBinding == nil, let firstBinding = gatewayManager.sortedAgentBindings.first {
            await switchAgent(firstBinding)
        }
    }

    /// Switch to a different agent binding.
    func switchAgent(_ binding: AgentBinding) async {
        let previousGatewayId = activeBinding?.gatewayId
        activeBinding = binding
        
        if previousGatewayId != binding.gatewayId {
            // Different gateway — reload sessions from the new gateway
            allGatewaySessions.removeAll()
            await refreshSessions()
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
        messageStore.clearAll()
        chatViewModels.removeAll()
    }

    // MARK: - Data loading

    /// Load agents and sessions after connecting.
    func loadInitialData() async {
        print("[AppViewModel] Loading initial data...")
        await refreshAgents()
        await refreshSessions()
        print("[AppViewModel] Loaded \(agents.count) agents, \(sessions.count) sessions")
    }

    /// Refresh agents from all connected gateways.
    func refreshAgents() async {
        var allAgents: [Agent] = []
        
        for (gatewayId, agentSummaries) in gatewayManager.agentSummaries {
            let gatewayAgents = agentSummaries.map { Agent(from: $0) }
            allAgents.append(contentsOf: gatewayAgents)
        }
        
        agents = allAgents
        print("[AppViewModel] Loaded \(agents.count) agents from \(gatewayManager.agentSummaries.count) gateways")
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
            print("[AppViewModel] sessions.list returned \(result.sessions.count) sessions for gateway \(binding.gatewayId)")

            // Build a lookup of existing createdAt values so we don't lose them on refresh.
            let existingCreatedAt = Dictionary(uniqueKeysWithValues:
                allGatewaySessions.map { ($0.key, $0.createdAt) }
            )

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
            print("[AppViewModel] Failed to list sessions: \(error)")
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

    // MARK: - Session actions

    /// Select a session and load its history.
    func selectSession(_ sessionKey: String) async {
        selectedSessionKey = sessionKey

        // Already have messages — nothing to load.
        guard !messageStore.hasMessages(for: sessionKey) else {
            print("[AppViewModel] selectSession(\(sessionKey)): already has messages, skipping")
            return
        }

        // Already loading this exact session — don't cancel and restart.
        guard historyLoadingKey != sessionKey else {
            print("[AppViewModel] selectSession(\(sessionKey)): already loading, skipping")
            return
        }

        // Cancel any in-flight load for a *different* session.
        if let previousKey = historyLoadingKey {
            print("[AppViewModel] selectSession(\(sessionKey)): cancelling load for \(previousKey)")
        }
        historyLoadTask?.cancel()
        historyLoadingKey = sessionKey

        print("[AppViewModel] selectSession(\(sessionKey)): starting history load")
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
            print("[AppViewModel] History load failed with limit=\(limit), waiting for reconnection...")
            let reconnected = await waitForReconnection(timeout: 15)
            guard reconnected else {
                print("[AppViewModel] ❌ Reconnection timed out for \(sessionKey)")
                return
            }
            print("[AppViewModel] Reconnected, retrying with smaller limit...")
        }
        print("[AppViewModel] ❌ All history load attempts failed for \(sessionKey)")
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
                print("[AppViewModel] chat.history failed: \(response.error?.message ?? "unknown")")
                return false
            }

            // Decode payload as raw dictionary to handle complex content field
            let payloadData = try JSONSerialization.data(withJSONObject: payload.value as Any)
            let payloadDict = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
            let rawMessages = payloadDict?["messages"] as? [[String: Any]] ?? []

            print("[AppViewModel] chat.history returned \(rawMessages.count) raw messages for \(sessionKey) (limit=\(limit))")

            let allMessages = rawMessages.enumerated().compactMap { index, raw in
                ChatMessage.fromHistory(raw, sessionKey: sessionKey, index: index)
            }.filter { $0.isVisible }

            // Merge consecutive assistant messages into a single message.
            // The gateway stores separate messages for each text segment
            // around tool calls, but the user sees them as one reply.
            let messages = Self.mergeConsecutiveAssistantMessages(allMessages)

            print("[AppViewModel] \(allMessages.count) visible → \(messages.count) after merging consecutive assistant messages")
            messageStore.setMessages(messages, for: sessionKey)
            return true
        } catch is CancellationError {
            // Expected when the user switches sessions before the load completes.
            print("[AppViewModel] History load cancelled (task cancellation) for \(sessionKey)")
            return false
        } catch GatewayClientError.cancelled {
            // Thrown when the WebSocket disconnects and all pending requests
            // are flushed (e.g. reconnection). Not a user-initiated cancel.
            print("[AppViewModel] History load interrupted (connection lost, limit=\(limit)) for \(sessionKey)")
            return false
        } catch {
            print("[AppViewModel] ❌ Failed to load history for \(sessionKey): \(type(of: error)) — \(error.localizedDescription)")
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
            print("[AppViewModel] Renamed session \(sessionKey) to '\(label)'")
        } catch {
            print("[AppViewModel] ❌ Failed to rename session: \(error)")
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
        print("[AppViewModel] Created new session: \(sessionKey)")
    }

    // MARK: - Event handling

    private func handleEvent(_ event: EventFrame, gatewayId: String) {
        switch event.event {
        case GatewayEvent.chat:
            handleChatEvent(event, gatewayId: gatewayId)

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

    private func handleChatEvent(_ event: EventFrame, gatewayId: String) {
        // Only handle events from the active gateway
        guard let activeBinding = activeBinding,
              activeBinding.gatewayId == gatewayId else {
            return
        }
        
        guard let payload = event.payload else {
            print("[AppViewModel] chat event has no payload")
            return
        }
        do {
            let chatEvent = try payload.decode(ChatEventPayload.self)
            print("[AppViewModel] chat event: state=\(chatEvent.state) runId=\(chatEvent.runId) sessionKey=\(chatEvent.sessionKey) content=\(chatEvent.message?.content?.prefix(80) ?? "nil")")
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
            print("[AppViewModel] ❌ Failed to decode chat event: \(error)")
            // Log the raw payload for debugging
            if let dict = payload.dictValue {
                print("[AppViewModel] Raw payload keys: \(dict.keys.sorted())")
                if let msg = dict["message"] as? [String: Any] {
                    print("[AppViewModel] message keys: \(msg.keys.sorted())")
                    print("[AppViewModel] content type: \(type(of: msg["content"] as Any))")
                }
            }
        }
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
    // MARK: - Message merging

    /// Merge consecutive assistant messages into single messages.
    ///
    /// The gateway transcript stores a separate message for each text segment
    /// around tool-call / tool-result pairs. When loaded as history these
    /// appear as multiple small bubbles for what was a single assistant turn.
    /// This method joins them so the UI shows one cohesive reply that can be
    /// selected and copied as a whole.
    static func mergeConsecutiveAssistantMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        guard !messages.isEmpty else { return [] }

        var merged: [ChatMessage] = []

        for message in messages {
            if message.role == .assistant,
               let last = merged.last,
               last.role == .assistant {
                // Append to the previous assistant message
                let separator = last.content.isEmpty || message.content.isEmpty ? "" : "\n\n"
                last.content += separator + message.content
                // Keep the earlier timestamp (start of the reply)
            } else {
                merged.append(message)
            }
        }

        return merged
    }
}
// Session.from(summary:) is defined in Session.swift
