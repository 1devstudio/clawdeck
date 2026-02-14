import Foundation

/// Represents an agent entry in the agent rail, binding a gateway agent to local customizations.
struct AgentBinding: Identifiable, Codable, Hashable {
    let id: String
    let gatewayId: String
    let agentId: String
    var localDisplayName: String?
    var localAvatarName: String?  // "sf:robot" for SF Symbols, or "filename.png" for custom
    var railOrder: Int

    /// Display name: local override ?? agent identity from gateway ?? agentId.capitalized
    func displayName(from gatewayManager: GatewayManager?) -> String {
        if let localDisplayName, !localDisplayName.isEmpty {
            return localDisplayName
        }
        
        // Try to get live agent name from gateway
        if let gatewayManager,
           let agentSummaries = gatewayManager.agentSummaries[gatewayId],
           let agentSummary = agentSummaries.first(where: { $0.id == agentId }),
           let name = agentSummary.name,
           !name.isEmpty {
            return name
        }
        
        return agentId.capitalized
    }

    /// Avatar: local override ?? live agent avatar from gateway ?? nil (show initials)
    func avatarName(from gatewayManager: GatewayManager?) -> String? {
        if let localAvatarName, !localAvatarName.isEmpty {
            return localAvatarName
        }
        
        // Try to get live agent avatar from gateway
        if let gatewayManager,
           let agentSummaries = gatewayManager.agentSummaries[gatewayId],
           let agentSummary = agentSummaries.first(where: { $0.id == agentId }),
           let avatar = agentSummary.avatar,
           !avatar.isEmpty {
            return avatar.hasPrefix("http") ? nil : "sf:\(avatar)" // Convert gateway icons to SF symbols
        }
        
        return nil
    }

    /// Initials for display (first 1-2 chars of displayName).
    func initials(from gatewayManager: GatewayManager?) -> String {
        let name = displayName(from: gatewayManager)
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    init(
        id: String = UUID().uuidString,
        gatewayId: String,
        agentId: String,
        localDisplayName: String? = nil,
        localAvatarName: String? = nil,
        railOrder: Int = 0
    ) {
        self.id = id
        self.gatewayId = gatewayId
        self.agentId = agentId
        self.localDisplayName = localDisplayName
        self.localAvatarName = localAvatarName
        self.railOrder = railOrder
    }
}

// MARK: - Persistence

extension AgentBinding {
    /// Key for UserDefaults storage.
    static let storageKey = "com.clawdbot.deck.agentBindings"

    /// Load saved bindings from UserDefaults.
    static func loadAll() -> [AgentBinding] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let bindings = try? JSONDecoder().decode([AgentBinding].self, from: data)
        else {
            return []
        }
        return bindings.sorted { $0.railOrder < $1.railOrder }
    }

    /// Save bindings to UserDefaults.
    static func saveAll(_ bindings: [AgentBinding]) {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}