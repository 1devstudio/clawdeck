import Foundation

// MARK: - Connection state

/// Observable connection state.
enum ConnectionState: String, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

/// Errors specific to the gateway client.
enum GatewayClientError: Error, LocalizedError {
    case notConnected
    case invalidURL
    case handshakeFailed(String)
    case requestFailed(ErrorShape)
    case timeout
    case encodingError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to gateway"
        case .invalidURL: return "Invalid gateway URL"
        case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
        case .requestFailed(let err): return "Request failed: \(err.message ?? "unknown")"
        case .timeout: return "Request timed out"
        case .encodingError(let msg): return "Encoding error: \(msg)"
        case .cancelled: return "Request cancelled"
        }
    }
}

// MARK: - Gateway Client Actor

/// Thread-safe WebSocket client for communicating with a Clawdbot gateway.
///
/// Lifecycle:
/// 1. Connect WebSocket to ws://host:port
/// 2. Receive event: connect.challenge with nonce
/// 3. Send req: connect with client info, auth token, device identity
/// 4. Receive res: hello-ok with protocol version, snapshot, features
/// 5. Now connected — send requests, receive events
actor GatewayClient {
    // MARK: - Properties

    private let profile: ConnectionProfile
    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession: URLSession
    private let deviceId: String

    /// Pending request continuations keyed by request ID.
    private var pendingRequests: [String: CheckedContinuation<ResponseFrame, Error>] = [:]

    /// Event stream for UI consumption.
    private var eventContinuation: AsyncStream<EventFrame>.Continuation?
    private(set) var eventStream: AsyncStream<EventFrame>

    /// Current connection state — updated on main actor for UI.
    @MainActor private(set) var state: ConnectionState = .disconnected

    /// Reconnect tracking.
    private var reconnectDelay: Double = GatewayProtocol.Reconnect.initialDelaySeconds
    private var shouldReconnect = false
    private var receiveTask: Task<Void, Never>?
    private var isHandshakeComplete = false

    /// Handshake result.
    private(set) var helloResult: HelloOk?

    // MARK: - Init

    init(profile: ConnectionProfile) {
        self.profile = profile
        self.urlSession = URLSession(configuration: .default)
        self.deviceId = Self.getOrCreateDeviceId()

        var continuation: AsyncStream<EventFrame>.Continuation!
        self.eventStream = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    deinit {
        eventContinuation?.finish()
        receiveTask?.cancel()
    }

    // MARK: - Connect

    /// Establish a WebSocket connection and perform the protocol handshake.
    func connect() async throws {
        guard let url = profile.webSocketURL else {
            throw GatewayClientError.invalidURL
        }

        await setState(.connecting)
        shouldReconnect = true
        reconnectDelay = GatewayProtocol.Reconnect.initialDelaySeconds

        let request = URLRequest(url: url)
        let task = urlSession.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        // Start receiving messages
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        // Wait for challenge + handshake (with timeout)
        try await performHandshake()
    }

    /// Disconnect from the gateway.
    func disconnect() {
        shouldReconnect = false
        isHandshakeComplete = false
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        cancelAllPendingRequests()
        Task { await setState(.disconnected) }
    }

    // MARK: - Send request

    /// Send a request and await the response.
    func send(method: String, params: (any Encodable)? = nil) async throws -> ResponseFrame {
        guard isHandshakeComplete else {
            throw GatewayClientError.notConnected
        }

        let requestId = UUID().uuidString
        let anyCodableParams: AnyCodable?

        if let params {
            let data = try JSONEncoder().encode(params)
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            anyCodableParams = AnyCodable(jsonObject)
        } else {
            anyCodableParams = nil
        }

        let frame = RequestFrame(id: requestId, method: method, params: anyCodableParams)
        try await sendFrame(frame)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestId] = continuation
        }
    }

    // MARK: - Convenience methods

    /// Send a chat message.
    func chatSend(sessionKey: String, message: String) async throws -> ChatSendResult {
        let params = ChatSendParams(sessionKey: sessionKey, message: message)
        let response = try await send(method: GatewayMethod.chatSend, params: params)
        guard response.ok, let payload = response.payload else {
            throw GatewayClientError.requestFailed(response.error ?? ErrorShape(code: nil, message: "Unknown error", details: nil))
        }
        return try payload.decode(ChatSendResult.self)
    }

    /// Fetch chat history for a session.
    func chatHistory(sessionKey: String, limit: Int = 50) async throws -> ChatHistoryResult {
        let params = ChatHistoryParams(sessionKey: sessionKey, limit: limit)
        let response = try await send(method: GatewayMethod.chatHistory, params: params)
        guard response.ok, let payload = response.payload else {
            throw GatewayClientError.requestFailed(response.error ?? ErrorShape(code: nil, message: "Unknown error", details: nil))
        }
        return try payload.decode(ChatHistoryResult.self)
    }

    /// Abort a running chat generation.
    func chatAbort(sessionKey: String) async throws {
        let params = ChatAbortParams(sessionKey: sessionKey)
        let _ = try await send(method: GatewayMethod.chatAbort, params: params)
    }

    /// List all sessions.
    func listSessions(limit: Int = 50) async throws -> SessionsListResult {
        let params = SessionsListParams(limit: limit, includeDerivedTitles: true, includeLastMessage: true)
        let response = try await send(method: GatewayMethod.sessionsList, params: params)
        guard response.ok, let payload = response.payload else {
            throw GatewayClientError.requestFailed(response.error ?? ErrorShape(code: nil, message: "Unknown error", details: nil))
        }
        return try payload.decode(SessionsListResult.self)
    }

    /// List all agents.
    func listAgents() async throws -> AgentsListResult {
        let response = try await send(method: GatewayMethod.agentsList)
        guard response.ok, let payload = response.payload else {
            throw GatewayClientError.requestFailed(response.error ?? ErrorShape(code: nil, message: "Unknown error", details: nil))
        }
        return try payload.decode(AgentsListResult.self)
    }

    /// Delete a session.
    func deleteSession(key: String) async throws {
        let params = SessionsDeleteParams(key: key)
        let _ = try await send(method: GatewayMethod.sessionsDelete, params: params)
    }

    /// Patch a session.
    func patchSession(key: String, label: String? = nil, model: String? = nil) async throws {
        let params = SessionsPatchParams(key: key, label: label, model: model)
        let _ = try await send(method: GatewayMethod.sessionsPatch, params: params)
    }

    // MARK: - Private: Handshake

    private func performHandshake() async throws {
        // The challenge event will be received in receiveLoop;
        // we use a continuation to await it.
        let challenge: ConnectChallenge = try await withCheckedThrowingContinuation { continuation in
            self.challengeContinuation = continuation
        }

        // Step 3: Send connect request
        let connectParams = ConnectParams(
            protocol_: GatewayProtocol.version,
            client: .init(
                name: GatewayProtocol.clientName,
                version: GatewayProtocol.clientVersion,
                platform: GatewayProtocol.platform
            ),
            auth: profile.token.map { ConnectParams.AuthInfo(token: $0) },
            device: .init(id: deviceId, name: deviceName)
        )

        let requestId = UUID().uuidString
        let paramsData = try JSONEncoder().encode(connectParams)
        let paramsJSON = try JSONSerialization.jsonObject(with: paramsData)
        let frame = RequestFrame(id: requestId, method: GatewayMethod.connect, params: AnyCodable(paramsJSON))
        try await sendFrame(frame)

        // Step 4: Await hello-ok response
        let response: ResponseFrame = try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestId] = continuation
        }

        guard response.ok else {
            let msg = response.error?.message ?? "Unknown handshake error"
            throw GatewayClientError.handshakeFailed(msg)
        }

        if let payload = response.payload {
            self.helloResult = try? payload.decode(HelloOk.self)
        }

        isHandshakeComplete = true
        reconnectDelay = GatewayProtocol.Reconnect.initialDelaySeconds
        await setState(.connected)
    }

    /// Continuation for waiting on the connect.challenge event.
    private var challengeContinuation: CheckedContinuation<ConnectChallenge, Error>?

    // MARK: - Private: Receive loop

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                let data: Data

                switch message {
                case .data(let d):
                    data = d
                case .string(let s):
                    guard let d = s.data(using: .utf8) else { continue }
                    data = d
                @unknown default:
                    continue
                }

                try handleReceivedData(data)
            } catch {
                // Connection lost
                if !Task.isCancelled {
                    await handleDisconnection()
                }
                return
            }
        }
    }

    private func handleReceivedData(_ data: Data) throws {
        let frame = try GatewayFrameDecoder.decode(from: data)

        switch frame {
        case .response(let response):
            if let continuation = pendingRequests.removeValue(forKey: response.id) {
                continuation.resume(returning: response)
            }

        case .event(let event):
            handleEvent(event)

        case .request:
            // Server shouldn't send requests to client, but handle gracefully
            break
        }
    }

    private func handleEvent(_ event: EventFrame) {
        // Handle connect.challenge during handshake
        if event.event == GatewayEvent.connectChallenge {
            if let continuation = challengeContinuation {
                challengeContinuation = nil
                if let payload = event.payload {
                    do {
                        let challenge = try payload.decode(ConnectChallenge.self)
                        continuation.resume(returning: challenge)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    // Empty challenge is valid
                    continuation.resume(returning: ConnectChallenge(nonce: ""))
                }
            }
            return
        }

        // Forward all other events to the stream
        eventContinuation?.yield(event)
    }

    // MARK: - Private: Send frame

    private func sendFrame(_ frame: RequestFrame) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [] // compact
        let data = try encoder.encode(frame)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw GatewayClientError.encodingError("Failed to convert frame to string")
        }
        try await webSocketTask?.send(.string(jsonString))
    }

    // MARK: - Private: Reconnection

    private func handleDisconnection() async {
        isHandshakeComplete = false
        cancelAllPendingRequests()

        guard shouldReconnect else {
            await setState(.disconnected)
            return
        }

        await setState(.reconnecting)

        while shouldReconnect && !Task.isCancelled {
            let delay = reconnectDelay
            reconnectDelay = min(
                reconnectDelay * GatewayProtocol.Reconnect.backoffMultiplier,
                GatewayProtocol.Reconnect.maxDelaySeconds
            )

            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard shouldReconnect else { break }

            do {
                try await connect()
                return // Successfully reconnected
            } catch {
                // Will retry after next delay
                continue
            }
        }

        await setState(.disconnected)
    }

    private func cancelAllPendingRequests() {
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: GatewayClientError.cancelled)
        }
        pendingRequests.removeAll()

        if let cc = challengeContinuation {
            challengeContinuation = nil
            cc.resume(throwing: GatewayClientError.cancelled)
        }
    }

    // MARK: - Private: State management

    @MainActor
    private func setState(_ newState: ConnectionState) {
        state = newState
    }

    // MARK: - Private: Device identity

    private var deviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "ClawdDeck"
        #endif
    }

    private static func getOrCreateDeviceId() -> String {
        let key = "com.clawdbot.deck.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
}
