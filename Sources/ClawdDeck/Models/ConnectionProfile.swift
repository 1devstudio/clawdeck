import Foundation

/// Configuration for connecting to a Clawdbot gateway instance.
struct ConnectionProfile: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var displayName: String
    var host: String
    var port: Int
    var path: String
    var useTLS: Bool
    var token: String?
    var isDefault: Bool
    var avatarName: String?  // "sf:robot" for SF Symbols, or "filename.png" for custom

    /// WebSocket URL for this profile.
    var webSocketURL: URL? {
        var components = URLComponents()
        components.scheme = useTLS ? "wss" : "ws"
        // Host may contain a path (e.g. "example.com/ws"), split it out.
        if let slashIndex = host.firstIndex(of: "/") {
            components.host = String(host[host.startIndex..<slashIndex])
            components.path = String(host[slashIndex...])
        } else {
            components.host = host
        }
        components.port = port
        return components.url
    }

    /// Display string for the connection.
    var displayAddress: String {
        let portSuffix = (useTLS && port == 443) || (!useTLS && port == 80) ? "" : ":\(port)"
        return "\(host)\(portSuffix)\(path)"
    }

    /// Initials for display (first 1-2 chars of displayName).
    var initials: String {
        let parts = displayName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    init(
        id: String = UUID().uuidString,
        name: String = "Default",
        displayName: String? = nil,
        host: String = "vps-0a60f62f.vps.ovh.net",
        port: Int = 443,
        path: String = "/ws",
        useTLS: Bool = true,
        token: String? = nil,
        isDefault: Bool = true,
        avatarName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName ?? name
        self.host = host
        self.port = port
        self.path = path
        self.useTLS = useTLS
        self.token = token
        self.isDefault = isDefault
        self.avatarName = avatarName
    }

    /// Default local development profile.
    static let localhost = ConnectionProfile(
        name: "Local",
        displayName: "Local",
        host: "localhost",
        port: 18789,
        path: "",
        useTLS: false,
        avatarName: "sf:desktopcomputer"
    )
}

// MARK: - Persistence

extension ConnectionProfile {
    /// Key for UserDefaults storage.
    static let storageKey = "com.clawdbot.deck.connectionProfiles"

    /// Load saved profiles from UserDefaults.
    static func loadAll() -> [ConnectionProfile] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let profiles = try? JSONDecoder().decode([ConnectionProfile].self, from: data)
        else {
            return []
        }
        return profiles
    }

    /// Save profiles to UserDefaults.
    static func saveAll(_ profiles: [ConnectionProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
