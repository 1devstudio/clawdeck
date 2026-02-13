import Foundation

/// Represents a chat session/conversation with one or more agents.
@Observable
final class Session: Identifiable, Hashable {
    let id: String
    let key: String
    var label: String?
    var derivedTitle: String?
    var model: String?
    var agentId: String?
    var lastMessage: String?
    var lastMessageAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var isActive: Bool

    /// Display title: explicit label > derived title > fallback
    var displayTitle: String {
        if let label, !label.isEmpty { return label }
        if let derivedTitle, !derivedTitle.isEmpty { return derivedTitle }
        return "Untitled Session"
    }

    init(
        id: String = UUID().uuidString,
        key: String,
        label: String? = nil,
        derivedTitle: String? = nil,
        model: String? = nil,
        agentId: String? = nil,
        lastMessage: String? = nil,
        lastMessageAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isActive: Bool = true
    ) {
        self.id = id
        self.key = key
        self.label = label
        self.derivedTitle = derivedTitle
        self.model = model
        self.agentId = agentId
        self.lastMessage = lastMessage
        self.lastMessageAt = lastMessageAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive
    }

    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.key == rhs.key
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }
}
