import Foundation

/// Probes for reachable Clawdbot gateways using a prioritised list of endpoints.
///
/// Usage:
/// ```swift
/// let prober = GatewayProber()
/// if let result = await prober.probeLocal() { ... }
/// if let result = await prober.probeRemote(host: "gw.example.com", token: "abc") { ... }
/// ```
actor GatewayProber {
    /// Seconds before a single probe attempt is abandoned.
    private let perProbeTimeout: TimeInterval = 3

    /// Result of a successful probe.
    struct ProbeResult: Sendable {
        let host: String
        let port: Int
        let useTLS: Bool
        let token: String?
        let agents: AgentsListResult
    }

    // MARK: - Local Detection (Scenario 1)

    /// Attempt to connect to a gateway on localhost.
    ///
    /// 1. Read `~/.clawdbot/clawdbot.json` for port + token.
    /// 2. Fall back to default port 18789 with no token.
    func probeLocal() async -> ProbeResult? {
        let localConfig = readLocalConfig()
        let port = localConfig?.port ?? 18789
        let token = localConfig?.token

        // Try with config values first
        if let result = await probe(host: "localhost", port: port, useTLS: false, token: token) {
            return result
        }

        // If config had a non-default port, also try default
        if port != 18789 {
            if let result = await probe(host: "localhost", port: 18789, useTLS: false, token: token) {
                return result
            }
        }

        // Try without token (in case config token is wrong)
        if token != nil {
            if let result = await probe(host: "localhost", port: port, useTLS: false, token: nil) {
                return result
            }
        }

        return nil
    }

    // MARK: - Remote Detection (Scenarios 2 & 3)

    /// Probe a remote host with smart endpoint ordering.
    ///
    /// - Domain names → TLS-first (VPS behind reverse proxy)
    /// - Private IPs / .local → direct-first (LAN)
    func probeRemote(host: String, token: String?) async -> ProbeResult? {
        let candidates: [(Int, Bool)]

        if isPrivateOrLocal(host) {
            // LAN — direct connection most likely
            candidates = [
                (18789, false),  // ws://host:18789
                (443, true),     // wss://host:443
                (80, false),     // ws://host:80
            ]
        } else {
            // Domain name — TLS via reverse proxy most likely
            candidates = [
                (443, true),     // wss://host:443
                (8443, true),    // wss://host:8443
                (18789, false),  // ws://host:18789
            ]
        }

        for (port, tls) in candidates {
            if let result = await probe(host: host, port: port, useTLS: tls, token: token) {
                return result
            }
        }

        return nil
    }

    /// Probe a specific endpoint with explicit settings (for Advanced mode).
    func probeDirect(host: String, port: Int, useTLS: Bool, token: String?) async -> ProbeResult? {
        return await probe(host: host, port: port, useTLS: useTLS, token: token)
    }

    // MARK: - Probe Status Reporting

    /// Description of the endpoint currently being probed (for UI feedback).
    static func probeDescription(host: String, port: Int, useTLS: Bool) -> String {
        let scheme = useTLS ? "wss" : "ws"
        let portSuffix = (useTLS && port == 443) || (!useTLS && port == 80) ? "" : ":\(port)"
        return "\(scheme)://\(host)\(portSuffix)"
    }

    // MARK: - Private

    /// Attempt a single probe: connect, handshake, list agents, disconnect.
    private func probe(host: String, port: Int, useTLS: Bool, token: String?) async -> ProbeResult? {
        let profile = GatewayProfile(
            host: host,
            port: port,
            path: "",
            useTLS: useTLS,
            token: token
        )

        let client = GatewayClient(profile: profile)

        do {
            try await withTimeout(seconds: perProbeTimeout) {
                try await client.connect()
            }
            let agents = try await withTimeout(seconds: perProbeTimeout) {
                try await client.listAgents()
            }
            await client.disconnect()

            return ProbeResult(
                host: host,
                port: port,
                useTLS: useTLS,
                token: token,
                agents: agents
            )
        } catch {
            await client.disconnect()
            return nil
        }
    }

    /// Execute an async operation with a timeout.
    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CancellationError()
            }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
        }
    }

    /// Determine if a host is a private/LAN address.
    private func isPrivateOrLocal(_ host: String) -> Bool {
        // .local Bonjour names
        if host.hasSuffix(".local") { return true }

        // Bare hostnames without dots (e.g. "macmini")
        if !host.contains(".") { return true }

        // Private IP ranges
        if host.hasPrefix("192.168.") { return true }
        if host.hasPrefix("10.") { return true }
        if host.hasPrefix("172.") {
            // 172.16.0.0 – 172.31.255.255
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }

        // Localhost variants
        if host == "127.0.0.1" || host == "::1" || host == "localhost" { return true }

        return false
    }

    /// Read port and token from the local Clawdbot config file.
    private func readLocalConfig() -> (port: Int, token: String?)? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path()
        let configPaths = [
            "\(homeDir)/.clawdbot/clawdbot.json",
            "\(homeDir)/.openclaw/clawdbot.json",
        ]

        for path in configPaths {
            guard let data = FileManager.default.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let gateway = json["gateway"] as? [String: Any]
            else { continue }

            let port = gateway["port"] as? Int ?? 18789

            var token: String? = nil
            if let auth = gateway["auth"] as? [String: Any] {
                token = auth["token"] as? String
            }

            return (port, token)
        }

        return nil
    }
}
