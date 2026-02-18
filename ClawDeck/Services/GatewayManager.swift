import Foundation

/// Manages multiple gateway connections simultaneously and provides a unified interface for the app.
@Observable
@MainActor
final class GatewayManager {
    // MARK: - Properties

    /// Gateway clients keyed by gateway profile ID.
    private(set) var clients: [String: GatewayClient] = [:]

    /// All configured gateway profiles.
    var gatewayProfiles: [GatewayProfile] = []

    /// All configured agent bindings.
    var agentBindings: [AgentBinding] = []

    /// Agent summaries keyed by gateway ID.
    var agentSummaries: [String: [AgentSummary]] = [:]

    /// Last connection error per gateway.
    var lastErrors: [String: String] = [:]

    /// Event processing tasks keyed by gateway ID.
    private var eventTasks: [String: Task<Void, Never>] = [:]

    /// In-memory cache for gateway tokens to avoid repeated Keychain prompts.
    private var tokenCache: [String: String] = [:]

    /// Handler for incoming events.
    var onEvent: ((EventFrame, String) -> Void)?  // (event, gatewayId)

    /// Handler for connection state changes.
    var onConnectionStateChange: ((ConnectionState, String) -> Void)?  // (newState, gatewayId)

    // MARK: - Init

    init() {
        loadProfiles()
        loadBindings()
    }

    // MARK: - Gateway Profile Management

    /// Add a new gateway profile.
    func addGatewayProfile(_ profile: GatewayProfile) {
        gatewayProfiles.append(profile)

        // Save token to keychain + memory cache if provided
        if let token = profile.token {
            KeychainHelper.saveGatewayToken(token, profileId: profile.id)
            tokenCache[profile.id] = token
        }

        saveGatewayProfiles()
    }

    /// Remove a gateway profile and disconnect if connected.
    func removeGatewayProfile(_ profile: GatewayProfile) {
        // Disconnect if connected
        if clients[profile.id] != nil {
            disconnectGateway(profile.id)
        }

        // Remove profile
        gatewayProfiles.removeAll { $0.id == profile.id }
        
        // Remove related agent bindings
        agentBindings.removeAll { $0.gatewayId == profile.id }
        
        // Clean up stored data
        agentSummaries.removeValue(forKey: profile.id)
        lastErrors.removeValue(forKey: profile.id)
        tokenCache.removeValue(forKey: profile.id)
        
        KeychainHelper.deleteGatewayToken(profileId: profile.id)
        saveGatewayProfiles()
        saveAgentBindings()
    }

    /// Update an existing gateway profile.
    func updateGatewayProfile(_ profile: GatewayProfile) {
        if let index = gatewayProfiles.firstIndex(where: { $0.id == profile.id }) {
            gatewayProfiles[index] = profile
            if let token = profile.token {
                KeychainHelper.saveGatewayToken(token, profileId: profile.id)
                tokenCache[profile.id] = token
            }
            saveGatewayProfiles()
        }
    }

    // MARK: - Agent Binding Management

    /// Add a new agent binding.
    func addAgentBinding(_ binding: AgentBinding) {
        // Set rail order to the end if not specified
        var newBinding = binding
        if newBinding.railOrder == 0 {
            newBinding.railOrder = (agentBindings.map { $0.railOrder }.max() ?? 0) + 1
        }
        
        agentBindings.append(newBinding)
        saveAgentBindings()
    }

    /// Remove an agent binding.
    func removeAgentBinding(_ binding: AgentBinding) {
        agentBindings.removeAll { $0.id == binding.id }
        saveAgentBindings()
    }

    /// Update an existing agent binding.
    func updateAgentBinding(_ binding: AgentBinding) {
        if let index = agentBindings.firstIndex(where: { $0.id == binding.id }) {
            agentBindings[index] = binding
            saveAgentBindings()
        }
    }

    /// Get agent bindings sorted by rail order.
    var sortedAgentBindings: [AgentBinding] {
        agentBindings.sorted { $0.railOrder < $1.railOrder }
    }

    // MARK: - Connection Management

    /// Get the client for a specific gateway ID.
    func client(for gatewayId: String) -> GatewayClient? {
        return clients[gatewayId]
    }

    /// Get the connection state for a gateway.
    func connectionState(for gatewayId: String) -> ConnectionState {
        guard let client = clients[gatewayId] else { return .disconnected }
        return client.state
    }

    /// Whether a gateway is connected.
    func isConnected(_ gatewayId: String) -> Bool {
        connectionState(for: gatewayId) == .connected
    }

    /// Connect to all configured gateways.
    func connectAll() async {
        await withTaskGroup(of: Void.self) { group in
            for profile in gatewayProfiles {
                group.addTask {
                    await self.connectGateway(profile.id)
                }
            }
        }
    }

    /// Connect to a specific gateway by profile ID.
    func connectGateway(_ gatewayId: String) async {
        guard let profile = gatewayProfiles.first(where: { $0.id == gatewayId }) else {
            lastErrors[gatewayId] = "Gateway profile not found"
            return
        }

        // Disconnect existing connection
        disconnectGateway(gatewayId)

        lastErrors.removeValue(forKey: gatewayId)

        // Resolve token: from profile, memory cache, or keychain (in that order).
        // The memory cache avoids repeated Keychain prompts on reconnect.
        var resolvedProfile = profile
        if resolvedProfile.token == nil {
            if let cached = tokenCache[profile.id] {
                resolvedProfile.token = cached
            } else if let keychainToken = KeychainHelper.loadGatewayToken(profileId: profile.id) {
                tokenCache[profile.id] = keychainToken
                resolvedProfile.token = keychainToken
            }
        }

        let client = GatewayClient(profile: resolvedProfile)
        clients[gatewayId] = client

        // Wire up connection state change notifications
        await client.setStateChangeHandler { [weak self] newState in
            self?.onConnectionStateChange?(newState, gatewayId)
        }

        // Start event processing
        eventTasks[gatewayId] = Task { [weak self] in
            for await event in await client.eventStream {
                await self?.handleEvent(event, gatewayId: gatewayId)
            }
        }

        do {
            try await client.connect()
            
            // After successful connection, load agents
            await loadAgentsForGateway(gatewayId)
        } catch {
            lastErrors[gatewayId] = error.localizedDescription
        }
    }

    /// Disconnect from a specific gateway.
    func disconnectGateway(_ gatewayId: String) {
        eventTasks[gatewayId]?.cancel()
        eventTasks.removeValue(forKey: gatewayId)

        if let client = clients[gatewayId] {
            Task {
                await client.disconnect()
            }
        }
        clients.removeValue(forKey: gatewayId)
    }

    /// Disconnect from all gateways.
    func disconnectAll() {
        for gatewayId in clients.keys {
            disconnectGateway(gatewayId)
        }
    }

    /// Reconnect to a specific gateway (disconnect + connect).
    func reconnect(gatewayId: String) async {
        disconnectGateway(gatewayId)
        await connectGateway(gatewayId)
    }

    // MARK: - Agent Loading

    /// Load agents for a specific gateway.
    private func loadAgentsForGateway(_ gatewayId: String) async {
        guard let client = clients[gatewayId] else { return }
        
        do {
            let result = try await client.listAgents()
            AppLogger.debug("Gateway \(gatewayId): agents.list returned \(result.agents.count) agents", category: "Network")
            agentSummaries[gatewayId] = result.agents
        } catch {
            AppLogger.error("Failed to list agents for gateway \(gatewayId): \(error)", category: "Network")
        }
    }

    /// Get available agents from all connected gateways that aren't already in the rail.
    func getAvailableAgents() -> [(gateway: GatewayProfile, agent: AgentSummary)] {
        var available: [(GatewayProfile, AgentSummary)] = []
        
        let existingKeys = Set(agentBindings.map { "\($0.gatewayId):\($0.agentId)" })
        
        for profile in gatewayProfiles {
            guard let agents = agentSummaries[profile.id] else { continue }
            for agent in agents {
                let key = "\(profile.id):\(agent.id)"
                if !existingKeys.contains(key) {
                    available.append((profile, agent))
                }
            }
        }
        
        return available.sorted(by: { $0.0.displayName < $1.0.displayName })
    }

    // MARK: - Convenience Methods

    /// Test a gateway connection without storing the profile.
    func testConnection(host: String, port: Int, path: String = "", useTLS: Bool, token: String?) async throws -> AgentsListResult {
        let testProfile = GatewayProfile(
            host: host,
            port: port,
            path: path,
            useTLS: useTLS,
            token: token
        )
        
        let client = GatewayClient(profile: testProfile)
        try await client.connect()
        
        let result = try await client.listAgents()
        
        await client.disconnect()
        
        return result
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: EventFrame, gatewayId: String) {
        onEvent?(event, gatewayId)
    }

    // MARK: - Private Persistence

    private func loadProfiles() {
        gatewayProfiles = GatewayProfile.loadAll()
    }

    private func saveGatewayProfiles() {
        // Strip tokens before saving to UserDefaults (they go in Keychain)
        let sanitized = gatewayProfiles.map { profile -> GatewayProfile in
            var p = profile
            p.token = nil
            return p
        }
        GatewayProfile.saveAll(sanitized)
    }
    
    private func loadBindings() {
        agentBindings = AgentBinding.loadAll()
    }
    
    private func saveAgentBindings() {
        AgentBinding.saveAll(agentBindings)
    }
}
