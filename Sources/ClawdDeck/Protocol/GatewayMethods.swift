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
        let id: String
        let version: String
        let platform: String
        let mode: String
    }

    struct AuthInfo: Codable, Sendable {
        let token: String?
        let password: String?
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

/// Lightweight agent representation from the gateway.
/// The gateway returns minimal info: just `id` and optionally a few fields.
struct AgentSummary: Codable, Sendable {
    let id: String
    let name: String?
    let avatar: String?
    let `default`: Bool?

    // The gateway may only return `id` — all other fields are optional.
}

/// Result of agents.list.
struct AgentsListResult: Codable, Sendable {
    let defaultId: String?
    let mainKey: String?
    let scope: String?
    let agents: [AgentSummary]
}

/// Result of agent.identity.
struct AgentIdentityResult: Codable, Sendable {
    let agentId: String
    let name: String?
    let avatar: String?
}

// MARK: - Session types

/// Session representation matching the actual gateway response.
/// The gateway returns timestamps as epoch milliseconds (numbers), not ISO strings.
struct SessionSummary: Codable, Sendable {
    let key: String
    let kind: String?               // "direct", "group", etc.
    let displayName: String?
    let channel: String?
    let chatType: String?
    let label: String?
    let derivedTitle: String?
    let lastMessagePreview: String?
    let sessionId: String?
    let model: String?
    let modelProvider: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let contextTokens: Int?
    let updatedAt: Double?          // epoch ms
    let systemSent: Bool?
    let abortedLastRun: Bool?

    // Nested structures
    let origin: SessionOrigin?
    let deliveryContext: DeliveryContext?

    struct SessionOrigin: Codable, Sendable {
        let label: String?
        let provider: String?
        let surface: String?
        let chatType: String?
    }

    struct DeliveryContext: Codable, Sendable {
        let channel: String?
        let to: String?
        let accountId: String?
    }
}

/// Parameters for sessions.list.
struct SessionsListParams: Codable, Sendable {
    let limit: Int?
    let includeDerivedTitles: Bool?
    let includeLastMessage: Bool?
    let agentId: String?
    let label: String?
    let search: String?

    init(limit: Int? = nil, includeDerivedTitles: Bool? = nil, includeLastMessage: Bool? = nil,
         agentId: String? = nil, label: String? = nil, search: String? = nil) {
        self.limit = limit
        self.includeDerivedTitles = includeDerivedTitles
        self.includeLastMessage = includeLastMessage
        self.agentId = agentId
        self.label = label
        self.search = search
    }
}

/// Result of sessions.list.
struct SessionsListResult: Codable, Sendable {
    let ts: Double?
    let path: String?
    let count: Int?
    let defaults: SessionDefaults?
    let sessions: [SessionSummary]

    struct SessionDefaults: Codable, Sendable {
        let modelProvider: String?
        let model: String?
        let contextTokens: Int?
    }
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
    let deleteTranscript: Bool?

    init(key: String, deleteTranscript: Bool? = nil) {
        self.key = key
        self.deleteTranscript = deleteTranscript
    }
}

// MARK: - Chat types

/// Parameters for chat.send.
struct ChatSendParams: Codable, Sendable {
    let sessionKey: String
    let message: String
    let idempotencyKey: String

    init(sessionKey: String, message: String, idempotencyKey: String = UUID().uuidString) {
        self.sessionKey = sessionKey
        self.message = message
        self.idempotencyKey = idempotencyKey
    }
}

/// Result of chat.send (acknowledgement).
struct ChatSendResult: Codable, Sendable {
    let runId: String?
    let sessionKey: String?
    let status: String?
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
    let runId: String?

    init(sessionKey: String, runId: String? = nil) {
        self.sessionKey = sessionKey
        self.runId = runId
    }
}

/// Payload of a `chat` event (streaming response).
struct ChatEventPayload: Codable, Sendable {
    let runId: String
    let sessionKey: String
    let seq: Int?
    let state: String  // "delta", "final", "aborted", "error"
    let message: ChatEventMessage?
    let errorMessage: String?
    let usage: AnyCodable?
    let stopReason: String?
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

// MARK: - Error shape

/// Gateway error details — used in response.error.
struct ErrorShape: Codable, Sendable {
    let code: String?
    let message: String?
    let details: AnyCodable?
    let retryable: Bool?
    let retryAfterMs: Int?
}
