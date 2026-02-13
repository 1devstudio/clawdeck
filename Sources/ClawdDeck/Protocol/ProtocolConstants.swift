import Foundation

/// Constants for the Clawdbot Gateway Protocol v3.
enum GatewayProtocol {
    static let version = 3
    static let clientName = "clawdbot-macos"
    static let clientVersion = "0.1.0"
    static let clientPlatform = "macos"
    static let clientMode = "ui"
    static let clientDisplayName = "Clawd Deck"
    static let role = "operator"
    static let scopes = ["operator.read", "operator.write", "operator.admin"]

    /// Default reconnect parameters.
    enum Reconnect {
        static let initialDelaySeconds: Double = 1.0
        static let maxDelaySeconds: Double = 30.0
        static let backoffMultiplier: Double = 2.0
    }
}

/// Gateway request method names.
enum GatewayMethod {
    static let connect = "connect"
    static let chatSend = "chat.send"
    static let chatHistory = "chat.history"
    static let chatAbort = "chat.abort"
    static let sessionsList = "sessions.list"
    static let sessionsPatch = "sessions.patch"
    static let sessionsDelete = "sessions.delete"
    static let agentsList = "agents.list"
    static let agentIdentity = "agent.identity"
    static let configGet = "config.get"
    static let configSchema = "config.schema"
    static let configPatch = "config.patch"
}

/// Gateway event names.
enum GatewayEvent {
    static let connectChallenge = "connect.challenge"
    static let chat = "chat"
    static let tick = "tick"
    static let presence = "presence"
    static let shutdown = "shutdown"
}

/// Chat event state values.
enum ChatEventState: String, Codable, Sendable {
    case delta
    case final_ = "final"
    case error
}

/// Gateway error codes.
enum GatewayErrorCode: String, Codable {
    case invalidRequest = "INVALID_REQUEST"
    case unauthorized = "UNAUTHORIZED"
    case forbidden = "FORBIDDEN"
    case notFound = "NOT_FOUND"
    case conflict = "CONFLICT"
    case rateLimited = "RATE_LIMITED"
    case internalError = "INTERNAL_ERROR"
    case unavailable = "UNAVAILABLE"
}
