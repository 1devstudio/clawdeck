import Foundation

/// Manages gateway connections and provides a unified interface for the app.
@Observable
@MainActor
final class ConnectionManager {
    // MARK: - Properties

    /// Active gateway client (currently single-connection; designed for multi).
    private(set) var activeClient: GatewayClient?

    /// All configured connection profiles.
    var profiles: [ConnectionProfile] = []

    /// Current connection state (forwarded from active client).
    var connectionState: ConnectionState {
        guard let client = activeClient else { return .disconnected }
        return client.state
    }

    /// Whether we're currently connected.
    var isConnected: Bool {
        connectionState == .connected
    }

    /// The active profile.
    private(set) var activeProfile: ConnectionProfile?

    /// Last connection error.
    var lastError: String?

    /// Event processing task.
    private var eventTask: Task<Void, Never>?

    /// Handler for incoming events.
    var onEvent: ((EventFrame) -> Void)?

    // MARK: - Init

    init() {
        loadProfiles()
    }

    // MARK: - Connection management

    /// Connect using the specified profile.
    func connect(with profile: ConnectionProfile) async {
        // Disconnect existing connection
        disconnect()

        activeProfile = profile
        lastError = nil

        // Resolve token: from profile or keychain
        var resolvedProfile = profile
        if resolvedProfile.token == nil {
            resolvedProfile.token = KeychainHelper.loadGatewayToken(profileId: profile.id)
        }

        let client = GatewayClient(profile: resolvedProfile)
        activeClient = client

        // Start event processing
        eventTask = Task { [weak self] in
            for await event in await client.eventStream {
                await self?.handleEvent(event)
            }
        }

        do {
            try await client.connect()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Connect using the default profile.
    func connectDefault() async {
        guard let defaultProfile = profiles.first(where: { $0.isDefault }) ?? profiles.first else {
            lastError = "No connection profiles configured"
            return
        }
        await connect(with: defaultProfile)
    }

    /// Disconnect the active connection.
    func disconnect() {
        eventTask?.cancel()
        eventTask = nil

        if let client = activeClient {
            Task {
                await client.disconnect()
            }
        }
        activeClient = nil
        activeProfile = nil
    }

    // MARK: - Profile management

    /// Add a new connection profile.
    func addProfile(_ profile: ConnectionProfile) {
        // If it's default, unset other defaults
        if profile.isDefault {
            for i in profiles.indices {
                profiles[i].isDefault = false
            }
        }

        profiles.append(profile)

        // Save token to keychain if provided
        if let token = profile.token {
            KeychainHelper.saveGatewayToken(token, profileId: profile.id)
        }

        saveProfiles()
    }

    /// Remove a connection profile.
    func removeProfile(_ profile: ConnectionProfile) {
        profiles.removeAll { $0.id == profile.id }
        KeychainHelper.deleteGatewayToken(profileId: profile.id)
        saveProfiles()
    }

    /// Update an existing profile.
    func updateProfile(_ profile: ConnectionProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            if let token = profile.token {
                KeychainHelper.saveGatewayToken(token, profileId: profile.id)
            }
            saveProfiles()
        }
    }

    // MARK: - Private

    private func handleEvent(_ event: EventFrame) {
        onEvent?(event)
    }

    private func loadProfiles() {
        profiles = ConnectionProfile.loadAll()
    }

    private func saveProfiles() {
        // Strip tokens before saving to UserDefaults (they go in Keychain)
        let sanitized = profiles.map { profile -> ConnectionProfile in
            var p = profile
            p.token = nil
            return p
        }
        ConnectionProfile.saveAll(sanitized)
    }
}
