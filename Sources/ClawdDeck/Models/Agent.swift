import Foundation

/// Represents a Clawdbot agent that can participate in conversations.
@Observable
final class Agent: Identifiable, Hashable {
    let id: String
    var name: String
    var avatarURL: URL?
    var isOnline: Bool
    var isDefault: Bool
    var metadata: [String: String]

    init(
        id: String,
        name: String,
        avatarURL: URL? = nil,
        isOnline: Bool = false,
        isDefault: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.isOnline = isOnline
        self.isDefault = isDefault
        self.metadata = metadata
    }

    static func == (lhs: Agent, rhs: Agent) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Factory from API response

extension Agent {
    /// Create an Agent from the gateway's AgentSummary.
    /// The gateway may only return `id` — name falls back to a capitalized id.
    convenience init(from summary: AgentSummary) {
        self.init(
            id: summary.id,
            name: summary.name ?? summary.id.capitalized,
            avatarURL: summary.avatar.flatMap { URL(string: $0) },
            isOnline: true,  // If listed by gateway, it's available
            isDefault: summary.default ?? false
        )
    }
}
