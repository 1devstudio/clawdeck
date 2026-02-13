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
        guard let client = connectionManager.activeClient else { return }

        // Check for snapshot data from handshake
        if let hello = await client.helloResult, let snapshot = hello.snapshot {
            if let agentSummaries = snapshot.agents {
                agents = agentSummaries.map { Agent(from: $0) }
            }
            if let sessionSummaries = snapshot.sessions {
                sessions = sessionSummaries.map { Session.from(summary: $0) }
            }
        }

        // Fetch fresh data
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshAgents() }
            group.addTask { await self.refreshSessions() }
        }
    }

    /// Refresh the agent list from the gateway.
    func refreshAgents() async {
        guard let client = connectionManager.activeClient else { return }
        do {
            let result = try await client.listAgents()
            agents = result.agents.map { Agent(from: $0) }
        } catch {
            // Silently fail — agents from snapshot are still available
        }
    }

    /// Refresh the session list from the gateway.
    func refreshSessions() async {
        guard let client = connectionManager.activeClient else { return }
        do {
            let result = try await client.listSessions()
            sessions = result.sessions.map { Session.from(summary: $0) }
        } catch {
            // Silently fail
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
            let result = try await client.chatHistory(sessionKey: sessionKey)
            let messages = result.messages.map { msg -> ChatMessage in
                ChatMessage(
                    id: msg.id ?? UUID().uuidString,
                    role: MessageRole(rawValue: msg.role) ?? .system,
                    content: msg.content,
                    timestamp: ISO8601DateFormatter().date(from: msg.timestamp ?? "") ?? Date(),
                    sessionKey: sessionKey,
                    state: .complete,
                    agentId: msg.agentId
                )
            }
            messageStore.setMessages(messages, for: sessionKey)
        } catch {
            // Failed to load history
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
        guard let payload = event.payload else { return }
        do {
            let chatEvent = try payload.decode(ChatEventPayload.self)
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
            // Failed to decode chat event
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

// MARK: - Session factory

extension Session {
    static func from(summary: SessionSummary) -> Session {
        let isoFormatter = ISO8601DateFormatter()
        return Session(
            key: summary.key,
            label: summary.label,
            derivedTitle: summary.derivedTitle,
            model: summary.model,
            agentId: summary.agentId,
            lastMessage: summary.lastMessage,
            lastMessageAt: summary.lastMessageAt.flatMap { isoFormatter.date(from: $0) },
            createdAt: summary.createdAt.flatMap { isoFormatter.date(from: $0) } ?? Date(),
            updatedAt: summary.updatedAt.flatMap { isoFormatter.date(from: $0) } ?? Date()
        )
    }
}
