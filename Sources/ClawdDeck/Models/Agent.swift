import Foundation

/// Represents a Clawdbot agent that can participate in conversations.
@Observable
final class Agent: Identifiable, Hashable {
    let id: String
    var name: String
    var avatarURL: URL?
    var isOnline: Bool
    var capabilities: [String]
    var metadata: [String: String]

    init(
        id: String,
        name: String,
        avatarURL: URL? = nil,
        isOnline: Bool = false,
        capabilities: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.isOnline = isOnline
        self.capabilities = capabilities
        self.metadata = metadata
    }

    static func == (lhs: Agent, rhs: Agent) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Decodable support for API responses

extension Agent {
    convenience init(from summary: AgentSummary) {
        self.init(
            id: summary.id,
            name: summary.name,
            avatarURL: summary.avatar.flatMap { URL(string: $0) },
            isOnline: summary.online ?? false
        )
    }
}
