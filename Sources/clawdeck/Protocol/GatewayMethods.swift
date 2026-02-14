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
/// The gateway schema is flat: { key, label?, model?, ... }
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

/// A single attachment to include in a chat.send request.
///
/// The gateway expects:
/// - `content`: base64-encoded file data (no data URL prefix)
/// - `mimeType`: e.g. "image/png", "image/jpeg"
/// - `fileName`: optional display name
struct ChatAttachment: Codable, Sendable {
    let content: String      // base64-encoded data
    let mimeType: String     // e.g. "image/png"
    let fileName: String?
    let type: String?        // e.g. "image"
}

/// Parameters for chat.send.
struct ChatSendParams: Codable, Sendable {
    let sessionKey: String
    let message: String
    let attachments: [ChatAttachment]?
    let idempotencyKey: String

    init(sessionKey: String, message: String, attachments: [ChatAttachment]? = nil, idempotencyKey: String = UUID().uuidString) {
        self.sessionKey = sessionKey
        self.message = message
        self.attachments = attachments?.isEmpty == true ? nil : attachments
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

/// A single content block within a chat event message.
///
/// Uses lenient decoding: if `type` is missing the block decodes as
/// `type: "unknown"` so one malformed block doesn't destroy the entire array.
struct ContentBlock: Sendable, Encodable {
    let type: String
    let text: String?
}

extension ContentBlock: Decodable {
    enum CodingKeys: String, CodingKey {
        case type, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"
        text = try? container.decodeIfPresent(String.self, forKey: .text)
    }
}

/// The message portion of a chat event.
///
/// The gateway sends `content` as an array of content blocks:
/// `[{"type":"text","text":"..."}]`
/// We decode the array and extract text blocks into a convenience property.
struct ChatEventMessage: Sendable {
    let role: String?
    let contentBlocks: [ContentBlock]?
    let agentId: String?

    /// Convenience: joined text from all "text" content blocks.
    var content: String? {
        guard let blocks = contentBlocks else { return nil }
        let texts = blocks.compactMap { $0.type == "text" ? $0.text : nil }
        return texts.isEmpty ? nil : texts.joined(separator: "\n\n")
    }
}

extension ChatEventMessage: Codable {
    enum CodingKeys: String, CodingKey {
        case role
        case content
        case agentId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        agentId = try container.decodeIfPresent(String.self, forKey: .agentId)

        // content can be either a plain string or an array of content blocks.
        // Use do/catch instead of try? so decode errors surface in logs.
        do {
            if let blocks = try container.decodeIfPresent([ContentBlock].self, forKey: .content) {
                contentBlocks = blocks
            } else {
                contentBlocks = nil
            }
        } catch {
            // Not an array — try plain string before giving up
            do {
                if let plainText = try container.decodeIfPresent(String.self, forKey: .content) {
                    contentBlocks = plainText.isEmpty ? nil : [ContentBlock(type: "text", text: plainText)]
                } else {
                    contentBlocks = nil
                }
            } catch {
                print("[ChatEventMessage] ⚠️ Failed to decode content as [ContentBlock] or String: \(error)")
                contentBlocks = nil
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(agentId, forKey: .agentId)
        try container.encodeIfPresent(contentBlocks, forKey: .content)
    }
}

// MARK: - Presence types

/// Payload of a presence event.
struct PresencePayload: Codable, Sendable {
    let agentId: String?
    let deviceId: String?
    let status: String?  // "online", "offline"
}

// MARK: - Config types

/// Result of config.get.
struct ConfigGetResult: Codable, Sendable {
    let path: String?
    let exists: Bool
    let raw: String?
    let hash: String?
    let valid: Bool?
    let issues: [String]?
    let warnings: [String]?
}

/// Parameters for config.patch.
struct ConfigPatchParams: Codable, Sendable {
    let raw: String
    let baseHash: String
    let sessionKey: String?
    let note: String?
    let restartDelayMs: Int?

    init(raw: String, baseHash: String, sessionKey: String? = nil, note: String? = nil, restartDelayMs: Int? = 2000) {
        self.raw = raw
        self.baseHash = baseHash
        self.sessionKey = sessionKey
        self.note = note
        self.restartDelayMs = restartDelayMs
    }
}

/// Result of config.schema — we only care about the uiHints for labels.
struct ConfigSchemaResult: Codable, Sendable {
    let schema: AnyCodable?
    let uiHints: [String: UIHintEntry]?
    let version: String?

    struct UIHintEntry: Codable, Sendable {
        let label: String?
        let help: String?
        let group: String?
        let order: Int?
        let sensitive: Bool?
        let placeholder: String?
        let advanced: Bool?
    }
}

// MARK: - Models

/// A single model entry returned by models.list.
struct GatewayModel: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let provider: String
    let contextWindow: Int?
    let reasoning: Bool?
    let input: [String]?
}

/// Result of models.list.
struct ModelsListResult: Codable, Sendable {
    let models: [GatewayModel]
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
