import Foundation
import SwiftUI

/// Root application state that owns all services and top-level data.
@Observable
@MainActor
final class AppViewModel {
    // MARK: - Services

    let connectionManager = ConnectionManager()
    let messageStore = MessageStore()

    // MARK: - State

    /// All known agents.
    var agents: [Agent] = []

    /// All known sessions.
    var sessions: [Session] = []

    /// Currently selected session key.
    var selectedSessionKey: String?

    /// Whether the inspector panel is visible.
    var isInspectorVisible = false

    /// Whether the onboarding/connection setup is shown.
    var showConnectionSetup = false

    /// Currently selected session.
    var selectedSession: Session? {
        sessions.first { $0.key == selectedSessionKey }
    }

    /// Whether the app has any configured profiles.
    var hasProfiles: Bool {
        !connectionManager.profiles.isEmpty
    }

    // MARK: - Init

    init() {
        // Wire up event handling
        connectionManager.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleEvent(event)
            }
        }

        // Show setup on first launch
        if !hasProfiles {
            showConnectionSetup = true
        }
    }

    // MARK: - Connection

    /// Connect using the default profile and load initial data.
    func connectAndLoad() async {
        await connectionManager.connectDefault()

        if connectionManager.isConnected {
            await loadInitialData()
        }
    }

    /// Connect with a specific profile and load initial data.
    func connect(with profile: ConnectionProfile) async {
        await connectionManager.connect(with: profile)

        if connectionManager.isConnected {
            await loadInitialData()
        }
    }

    /// Disconnect from the gateway.
    func disconnect() {
        connectionManager.disconnect()
        agents.removeAll()
        sessions.removeAll()
        selectedSessionKey = nil
        messageStore.clearAll()
    }

    // MARK: - Data loading

    /// Load agents and sessions after connecting.
    func loadInitialData() async {
        guard connectionManager.activeClient != nil else {
            print("[AppViewModel] No active client, skipping data load")
            return
        }

        // Fetch fresh data from gateway (skip snapshot — it's complex to decode)
        print("[AppViewModel] Loading initial data...")
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshAgents() }
            group.addTask { await self.refreshSessions() }
        }
        print("[AppViewModel] Loaded \(agents.count) agents, \(sessions.count) sessions")
    }

    /// Refresh the agent list from the gateway.
    func refreshAgents() async {
        guard let client = connectionManager.activeClient else { return }
        do {
            let result = try await client.listAgents()
            print("[AppViewModel] agents.list returned \(result.agents.count) agents (default: \(result.defaultId ?? "none"))")
            agents = result.agents.map { Agent(from: $0) }
        } catch {
            print("[AppViewModel] Failed to list agents: \(error)")
        }
    }

    /// Refresh the session list from the gateway.
    func refreshSessions() async {
        guard let client = connectionManager.activeClient else { return }
        do {
            let result = try await client.listSessions()
            print("[AppViewModel] sessions.list returned \(result.sessions.count) sessions")
            sessions = result.sessions
                .sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
                .map { Session.from(summary: $0) }
        } catch {
            print("[AppViewModel] Failed to list sessions: \(error)")
        }
    }

    // MARK: - Session actions

    /// Select a session and load its history.
    func selectSession(_ sessionKey: String) async {
        selectedSessionKey = sessionKey

        // Load history if not already loaded
        if !messageStore.hasMessages(for: sessionKey) {
            await loadHistory(for: sessionKey)
        }
    }

    /// Load chat history for a session.
    func loadHistory(for sessionKey: String) async {
        guard let client = connectionManager.activeClient else { return }
        do {
            let response = try await client.send(
                method: GatewayMethod.chatHistory,
                params: ChatHistoryParams(sessionKey: sessionKey, limit: 100)
            )
            guard response.ok, let payload = response.payload else {
                print("[AppViewModel] chat.history failed: \(response.error?.message ?? "unknown")")
                return
            }

            // Decode payload as raw dictionary to handle complex content field
            let payloadData = try JSONSerialization.data(withJSONObject: payload.value as Any)
            let payloadDict = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
            let rawMessages = payloadDict?["messages"] as? [[String: Any]] ?? []

            print("[AppViewModel] chat.history returned \(rawMessages.count) raw messages for \(sessionKey)")

            let messages = rawMessages.enumerated().compactMap { index, raw in
                ChatMessage.fromHistory(raw, sessionKey: sessionKey, index: index)
            }.filter { $0.isVisible }

            print("[AppViewModel] \(messages.count) visible messages after filtering")
            messageStore.setMessages(messages, for: sessionKey)
        } catch {
            print("[AppViewModel] Failed to load history: \(error)")
        }
    }

    /// Delete a session.
    func deleteSession(_ sessionKey: String) async {
        guard let client = connectionManager.activeClient else { return }
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
        guard let client = connectionManager.activeClient else { return }
        do {
            try await client.patchSession(key: sessionKey, label: label)
            if let session = sessions.first(where: { $0.key == sessionKey }) {
                session.label = label
            }
        } catch {
            // Handle error
        }
    }

    // MARK: - Event handling

    private func handleEvent(_ event: EventFrame) {
        switch event.event {
        case GatewayEvent.chat:
            handleChatEvent(event)

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

    private func handleChatEvent(_ event: EventFrame) {
        guard let payload = event.payload else {
            print("[AppViewModel] chat event has no payload")
            return
        }
        do {
            let chatEvent = try payload.decode(ChatEventPayload.self)
            print("[AppViewModel] chat event: state=\(chatEvent.state) runId=\(chatEvent.runId) sessionKey=\(chatEvent.sessionKey) content=\(chatEvent.message?.content?.prefix(80) ?? "nil")")
            messageStore.handleChatEvent(chatEvent)

            // Update session's last message
            if chatEvent.state == "final", let content = chatEvent.message?.content {
                if let session = sessions.first(where: { $0.key == chatEvent.sessionKey }) {
                    session.lastMessage = String(content.prefix(100))
                    session.lastMessageAt = Date()
                    session.updatedAt = Date()
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
}
// Session.from(summary:) is defined in Session.swift
