import Foundation

// MARK: - Connection handshake

/// Parameters for the connect request (step 3 of handshake).
struct ConnectParams: Codable, Sendable {
    let minProtocol: Int
    let maxProtocol: Int
    let client: ClientInfo
    let auth: AuthInfo?
    let device: DeviceInfo?

    struct ClientInfo: Codable, Sendable {
        let id: String
        let version: String
        let platform: String
        let mode: String
    }

    struct AuthInfo: Codable, Sendable {
        let token: String
    }

    struct DeviceInfo: Codable, Sendable {
        let id: String
        let publicKey: String
        let signature: String
        let signedAt: Int
    }
}

/// Payload of the connect.challenge event (step 2 of handshake).
struct ConnectChallenge: Codable, Sendable {
    let nonce: String
}

/// Payload of the hello-ok response (step 4 of handshake).
struct HelloOk: Codable, Sendable {
    let protocolVersion: Int?
    let sessionId: String?
    let features: [String]?
    let snapshot: SnapshotPayload?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol"
        case sessionId, features, snapshot
    }
}

/// Initial state snapshot delivered with hello-ok.
struct SnapshotPayload: Codable, Sendable {
    let agents: [AgentSummary]?
    let sessions: [SessionSummary]?
}

// MARK: - Agent types

/// Lightweight agent representation from the API.
struct AgentSummary: Codable, Sendable {
    let id: String
    let name: String
    let avatar: String?
    let online: Bool?
    let capabilities: [String]?
}

/// Result of agents.list.
struct AgentsListResult: Codable, Sendable {
    let agents: [AgentSummary]
}

/// Result of agent.identity.
struct AgentIdentityResult: Codable, Sendable {
    let id: String
    let name: String
    let avatar: String?
    let model: String?
}

// MARK: - Session types

/// Lightweight session representation from the API.
struct SessionSummary: Codable, Sendable {
    let key: String
    let label: String?
    let derivedTitle: String?
    let model: String?
    let agentId: String?
    let lastMessage: String?
    let lastMessageAt: String?
    let createdAt: String?
    let updatedAt: String?
}

/// Parameters for sessions.list.
struct SessionsListParams: Codable, Sendable {
    let limit: Int?
    let includeDerivedTitles: Bool?
    let includeLastMessage: Bool?
}

/// Result of sessions.list.
struct SessionsListResult: Codable, Sendable {
    let sessions: [SessionSummary]
}

/// Parameters for sessions.patch.
struct SessionsPatchParams: Codable, Sendable {
    let key: String
    let label: String?
    let model: String?
}

/// Parameters for sessions.delete.
struct SessionsDeleteParams: Codable, Sendable {
    let key: String
}

// MARK: - Chat types

/// Parameters for chat.send.
struct ChatSendParams: Codable, Sendable {
    let sessionKey: String
    let message: String
    let idempotencyKey: String?

    init(sessionKey: String, message: String, idempotencyKey: String? = UUID().uuidString) {
        self.sessionKey = sessionKey
        self.message = message
        self.idempotencyKey = idempotencyKey
    }
}

/// Result of chat.send (acknowledgement).
struct ChatSendResult: Codable, Sendable {
    let runId: String?
    let sessionKey: String?
}

/// Parameters for chat.history.
struct ChatHistoryParams: Codable, Sendable {
    let sessionKey: String
    let limit: Int?
}

/// A single message in the chat history response.
struct HistoryMessage: Codable, Sendable {
    let id: String?
    let role: String
    let content: String
    let timestamp: String?
    let agentId: String?
}

/// Result of chat.history.
struct ChatHistoryResult: Codable, Sendable {
    let messages: [HistoryMessage]
}

/// Parameters for chat.abort.
struct ChatAbortParams: Codable, Sendable {
    let sessionKey: String
}

/// Payload of a `chat` event (streaming response).
struct ChatEventPayload: Codable, Sendable {
    let runId: String
    let sessionKey: String
    let seq: Int?
    let state: String  // "delta", "final", "error"
    let message: ChatEventMessage?
    let error: ErrorShape?
}

/// The message portion of a chat event.
struct ChatEventMessage: Codable, Sendable {
    let role: String?
    let content: String?
    let agentId: String?
}

// MARK: - Presence types

/// Payload of a presence event.
struct PresencePayload: Codable, Sendable {
    let agentId: String?
    let deviceId: String?
    let status: String?  // "online", "offline"
}
