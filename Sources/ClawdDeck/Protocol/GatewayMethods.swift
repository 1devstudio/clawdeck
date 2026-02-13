import Foundation

// MARK: - Connection handshake

/// Parameters for the connect request (step 3 of handshake).
struct ConnectParams: Codable, Sendable {
    let minProtocol: Int
    let maxProtocol: Int
    let client: ClientInfo
    let role: String
    let scopes: [String]
    let auth: AuthInfo?
    let device: DeviceInfo?
    let locale: String?
    let userAgent: String?

    struct ClientInfo: Codable, Sendable {
        let id: String       // "clawdbot-macos"
        let version: String  // "0.1.0"
        let platform: String // "macos"
        let mode: String     // "ui"
        let displayName: String?
    }

    struct AuthInfo: Codable, Sendable {
        let token: String?
        let password: String?
    }

    struct DeviceInfo: Codable, Sendable {
        let id: String
        let publicKey: String?
        let signature: String?
        let signedAt: Int?
        let nonce: String?
    }
}

/// Payload of the connect.challenge event (step 2 of handshake).
struct ConnectChallenge: Codable, Sendable {
    let nonce: String
}

/// Payload of the hello-ok response (step 4 of handshake).
struct HelloOk: Codable, Sendable {
    let type: String                // "hello-ok"
    let `protocol`: Int             // 3
    let server: ServerInfo
    let features: FeaturesInfo
    let snapshot: AnyCodable?
    let canvasHostUrl: String?
    let auth: AuthResponse?
    let policy: PolicyInfo

    struct ServerInfo: Codable, Sendable {
        let version: String
        let commit: String?
        let host: String?
        let connId: String
    }

    struct FeaturesInfo: Codable, Sendable {
        let methods: [String]
        let events: [String]
    }

    struct AuthResponse: Codable, Sendable {
        let deviceToken: String
        let role: String
        let scopes: [String]
        let issuedAtMs: Int?
    }

    struct PolicyInfo: Codable, Sendable {
        let maxPayload: Int
        let maxBufferedBytes: Int
        let tickIntervalMs: Int
    }
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
