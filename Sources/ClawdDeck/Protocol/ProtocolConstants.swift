import Foundation

/// Constants for the Clawdbot Gateway Protocol v3.
enum GatewayProtocol {
    static let version = 3
    static let clientName = "ClawdDeck"
    static let clientVersion = "0.1.0"
    static let platform = "macOS"

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
enum GatewayErrorCode: Int, Codable {
    case unknown = -1
    case badRequest = 400
    case unauthorized = 401
    case forbidden = 403
    case notFound = 404
    case conflict = 409
    case rateLimited = 429
    case internalError = 500
    case unavailable = 503
}
