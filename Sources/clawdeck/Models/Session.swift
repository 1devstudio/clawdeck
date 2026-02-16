import Foundation

/// Represents a chat session/conversation with one or more agents.
@Observable
final class Session: Identifiable, Hashable {
    let id: String
    let key: String
    var label: String?
    var derivedTitle: String?
    var displayName: String?
    var channel: String?
    var kind: String?
    var model: String?
    var modelProvider: String?
    var agentId: String?
    var lastMessage: String?
    var lastMessageAt: Date?
    /// When the session was first seen (stable sort key).
    var createdAt: Date
    var updatedAt: Date
    var isActive: Bool
    var totalTokens: Int?
    var contextTokens: Int?

    /// Display title: explicit label > display name > derived title > session key
    var displayTitle: String {
        if let label, !label.isEmpty { return label }
        if let displayName, !displayName.isEmpty { return cleanDisplayName(displayName) }
        if let derivedTitle, !derivedTitle.isEmpty {
            // Trim long derived titles
            let trimmed = derivedTitle.prefix(60)
            return trimmed.count < derivedTitle.count ? "\(trimmed)…" : derivedTitle
        }
        return shortKey
    }

    /// Short key for display (e.g., "main" from "agent:main:main")
    var shortKey: String {
        let parts = key.split(separator: ":")
        if parts.count >= 3 {
            return String(parts.last ?? Substring(key))
        }
        return key
    }

    /// Subtitle text (channel, model, etc.)
    var subtitle: String? {
        var parts: [String] = []
        if let channel, !channel.isEmpty { parts.append(channel) }
        if let model, !model.isEmpty { parts.append(model) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    init(
        id: String = UUID().uuidString,
        key: String,
        label: String? = nil,
        derivedTitle: String? = nil,
        displayName: String? = nil,
        channel: String? = nil,
        kind: String? = nil,
        model: String? = nil,
        modelProvider: String? = nil,
        agentId: String? = nil,
        lastMessage: String? = nil,
        lastMessageAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isActive: Bool = true,
        totalTokens: Int? = nil,
        contextTokens: Int? = nil
    ) {
        self.id = id
        self.key = key
        self.label = label
        self.derivedTitle = derivedTitle
        self.displayName = displayName
        self.channel = channel
        self.kind = kind
        self.model = model
        self.modelProvider = modelProvider
        self.agentId = agentId
        self.lastMessage = lastMessage
        self.lastMessageAt = lastMessageAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive
        self.totalTokens = totalTokens
        self.contextTokens = contextTokens
    }

    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.key == rhs.key
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }

    private func cleanDisplayName(_ name: String) -> String {
        // Clean up gateway display names like "webchat:g-agent-main-main"
        if name.hasPrefix("webchat:") {
            return String(name.dropFirst("webchat:".count))
        }
        return name
    }
}

// MARK: - Factory from gateway response

extension Session {
    /// Create a Session from the gateway's SessionSummary.
    static func from(summary: SessionSummary) -> Session {
        let updatedDate: Date
        if let ts = summary.updatedAt {
            updatedDate = Date(timeIntervalSince1970: ts / 1000.0)  // epoch ms → Date
        } else {
            updatedDate = Date()
        }

        // Extract agent ID from session key (e.g., "agent:main:main" → "main")
        let agentId: String? = {
            let parts = summary.key.split(separator: ":")
            if parts.count >= 2 {
                return String(parts[1])
            }
            return nil
        }()

        return Session(
            key: summary.key,
            label: summary.label,
            derivedTitle: summary.derivedTitle,
            displayName: summary.displayName,
            channel: summary.channel ?? summary.origin?.surface,
            kind: summary.kind,
            model: summary.model,
            modelProvider: summary.modelProvider,
            agentId: agentId,
            lastMessage: summary.lastMessagePreview,
            lastMessageAt: updatedDate,
            createdAt: updatedDate,  // Best proxy; stable after first load
            updatedAt: updatedDate,
            isActive: true,
            totalTokens: summary.totalTokens,
            contextTokens: summary.contextTokens
        )
    }
}
