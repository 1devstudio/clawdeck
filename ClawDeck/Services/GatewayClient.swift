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
    case timeout(method: String, seconds: TimeInterval)
    case encodingError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to gateway"
        case .invalidURL: return "Invalid gateway URL"
        case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
        case .requestFailed(let err): return "Request failed: \(err.message ?? "unknown")"
        case .timeout(let method, let seconds): return "\(method) timed out after \(Int(seconds))s"
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
/// 2. Receive event: connect.challenge
/// 3. Send req: connect with client info and auth token
/// 4. Receive res: hello-ok with protocol version, snapshot, features
/// 5. Now connected — send requests, receive events
actor GatewayClient {
    // MARK: - Properties

    private let profile: GatewayProfile
    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession: URLSession

    /// Pending request continuations keyed by request ID.
    private var pendingRequests: [String: CheckedContinuation<ResponseFrame, Error>] = [:]

    /// Event stream for UI consumption.
    private var eventContinuation: AsyncStream<EventFrame>.Continuation?
    private(set) var eventStream: AsyncStream<EventFrame>

    /// Current connection state — updated on main actor for UI.
    @MainActor private(set) var state: ConnectionState = .disconnected

    /// Callback invoked on @MainActor whenever connection state changes.
    /// Set once before connect(), read from @MainActor setState() — no race.
    nonisolated(unsafe) private var stateChangeHandler: (@MainActor @Sendable (ConnectionState) -> Void)?

    /// Set a handler to be called on @MainActor when connection state transitions.
    func setStateChangeHandler(_ handler: @escaping @MainActor @Sendable (ConnectionState) -> Void) {
        stateChangeHandler = handler
    }

    /// Reconnect tracking.
    private var reconnectDelay: Double = GatewayProtocol.Reconnect.initialDelaySeconds
    private var shouldReconnect = false
    private var receiveTask: Task<Void, Never>?
    private var isHandshakeComplete = false

    /// Handshake result.
    private(set) var helloResult: HelloOk?

    // MARK: - Init

    init(profile: GatewayProfile) {
        self.profile = profile
        self.urlSession = URLSession(configuration: .default)

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

        // Clean up any previous connection attempt
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        cancelAllPendingRequests()
        isHandshakeComplete = false

        await setState(.connecting)
        shouldReconnect = true

        let task = urlSession.webSocketTask(with: url)
        // Default maximumMessageSize is 1 MB — far too small for large
        // chat.history responses (sessions with many tool calls can produce
        // multi-megabyte payloads). Raise to 50 MB.
        task.maximumMessageSize = 50 * 1024 * 1024
        self.webSocketTask = task
        task.resume()

        // Perform handshake by receiving directly on the WebSocket —
        // no separate Task needed, so there's no actor scheduling delay.
        do {
            try await performHandshake()
        } catch {
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            await setState(.disconnected)
            throw error
        }

        // Handshake succeeded — start the receive loop for normal operation
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
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
    ///
    /// Supports cooperative cancellation: if the calling `Task` is cancelled
    /// while waiting for the gateway response, the pending continuation is
    /// immediately resumed with `CancellationError` and removed from the
    /// in-flight dictionary so it doesn't leak.
    ///
    /// A timeout (default 30s) prevents the request from hanging indefinitely
    /// if the gateway accepts the frame but never responds.
    func send(method: String, params: (any Encodable)? = nil, timeout: TimeInterval = 30) async throws -> ResponseFrame {
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

        // Start a timeout watchdog that expires the pending request
        // if the gateway never responds.
        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self?.timeoutPendingRequest(id: requestId, method: method, timeout: timeout)
            } catch {
                // Sleep cancelled — response arrived before timeout.
            }
        }
        defer { timeoutTask.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // If the task was already cancelled before we got here,
                // resume immediately instead of parking the continuation.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    pendingRequests[requestId] = continuation
                }
            }
        } onCancel: {
            // Called on an arbitrary thread when the parent Task is cancelled.
            // We need to hop onto the actor to safely mutate pendingRequests.
            Task { [weak self] in
                await self?.cancelPendingRequest(id: requestId)
            }
        }
    }

    /// Cancel a single pending request by its ID.
    /// Called from the cancellation handler when the calling task is cancelled.
    private func cancelPendingRequest(id: String) {
        if let continuation = pendingRequests.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        }
    }

    /// Expire a pending request that exceeded its timeout.
    /// Actor serialization ensures only one of response / timeout / cancel
    /// will find the continuation — the others see nothing and return.
    private func timeoutPendingRequest(id: String, method: String, timeout: TimeInterval) {
        if let continuation = pendingRequests.removeValue(forKey: id) {
            continuation.resume(throwing: GatewayClientError.timeout(method: method, seconds: timeout))
        }
    }

    // MARK: - Convenience methods

    /// Send a chat message, optionally with image attachments.
    func chatSend(sessionKey: String, message: String, attachments: [ChatAttachment]? = nil) async throws -> ChatSendResult {
        let params = ChatSendParams(sessionKey: sessionKey, message: message, attachments: attachments)
        let response = try await send(method: GatewayMethod.chatSend, params: params)
        guard response.ok, let payload = response.payload else {
            throw GatewayClientError.requestFailed(response.error ?? ErrorShape(code: nil, message: "Unknown error", details: nil, retryable: nil, retryAfterMs: nil))
        }
        return try payload.decode(ChatSendResult.self)
    }

    /// Fetch chat history for a session.
    func chatHistory(sessionKey: String, limit: Int = 50) async throws -> ChatHistoryResult {
        let params = ChatHistoryParams(sessionKey: sessionKey, limit: limit)
        let response = try await send(method: GatewayMethod.chatHistory, params: params)
        guard response.ok, let payload = response.payload else {
            throw GatewayClientError.requestFailed(response.error ?? ErrorShape(code: nil, message: "Unknown error", details: nil, retryable: nil, retryAfterMs: nil))
        }
        return try payload.decode(ChatHistoryResult.self)
    }

    /// Abort a running chat generation.
    func chatAbort(sessionKey: String) async throws {
        let params = ChatAbortParams(sessionKey: sessionKey)
        let _ = try await send(method: GatewayMethod.chatAbort, params: params)
    }

    /// List all sessions, optionally filtered to a specific agent.
    func listSessions(limit: Int = 50, agentId: String? = nil) async throws -> SessionsListResult {
        let params = SessionsListParams(limit: limit, includeDerivedTitles: true, includeLastMessage: true, agentId: agentId)
        let response = try await send(method: GatewayMethod.sessionsList, params: params)
        guard response.ok, let payload = response.payload else {
            throw GatewayClientError.requestFailed(response.error ?? ErrorShape(code: nil, message: "Unknown error", details: nil, retryable: nil, retryAfterMs: nil))
        }
        return try payload.decode(SessionsListResult.self)
    }

    /// List all agents.
    func listAgents() async throws -> AgentsListResult {
        let response = try await send(method: GatewayMethod.agentsList)
        guard response.ok, let payload = response.payload else {
            throw GatewayClientError.requestFailed(response.error ?? ErrorShape(code: nil, message: "Unknown error", details: nil, retryable: nil, retryAfterMs: nil))
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

    // MARK: - Cron

    /// List all cron jobs (including disabled).
    func cronList() async throws -> CronListResult {
        let params = CronListParams(includeDisabled: true)
        let response = try await send(method: GatewayMethod.cronList, params: params)
        guard response.ok, let payload = response.payload else {
            throw GatewayClientError.requestFailed(response.error ?? ErrorShape(code: nil, message: "Unknown error", details: nil, retryable: nil, retryAfterMs: nil))
        }
        return try payload.decode(CronListResult.self)
    }

    /// Fetch run history for a cron job.
    func cronRuns(jobId: String, limit: Int = 10) async throws -> CronRunsResult {
        let params = CronRunsParams(jobId: jobId, limit: limit)
        let response = try await send(method: GatewayMethod.cronRuns, params: params)
        guard response.ok, let payload = response.payload else {
            throw GatewayClientError.requestFailed(response.error ?? ErrorShape(code: nil, message: "Unknown error", details: nil, retryable: nil, retryAfterMs: nil))
        }
        return try payload.decode(CronRunsResult.self)
    }

    /// Update a cron job (e.g. enable/disable, change prompt).
    func cronUpdate(jobId: String, enabled: Bool? = nil, payloadKind: String? = nil, message: String? = nil) async throws {
        let payloadPatch: CronUpdateParams.PayloadPatch? = if let payloadKind, let message {
            CronUpdateParams.PayloadPatch(kind: payloadKind, message: message)
        } else {
            nil
        }
        let patch = CronUpdateParams.CronUpdatePatch(enabled: enabled, payload: payloadPatch)
        let params = CronUpdateParams(id: jobId, patch: patch)
        let response = try await send(method: GatewayMethod.cronUpdate, params: params)
        guard response.ok else {
            throw GatewayClientError.requestFailed(response.error ?? ErrorShape(code: nil, message: "Unknown error", details: nil, retryable: nil, retryAfterMs: nil))
        }
    }

    /// Remove a cron job.
    func cronRemove(jobId: String) async throws {
        let params = CronRemoveParams(jobId: jobId)
        let response = try await send(method: GatewayMethod.cronRemove, params: params)
        guard response.ok else {
            throw GatewayClientError.requestFailed(response.error ?? ErrorShape(code: nil, message: "Unknown error", details: nil, retryable: nil, retryAfterMs: nil))
        }
    }

    /// Fetch the current gateway config.
    func configGet() async throws -> ConfigGetResult {
        let response = try await send(method: GatewayMethod.configGet)
        guard response.ok, let payload = response.payload else {
            throw GatewayClientError.requestFailed(response.error ?? ErrorShape(code: nil, message: "Unknown error", details: nil, retryable: nil, retryAfterMs: nil))
        }
        return try payload.decode(ConfigGetResult.self)
    }

    /// Fetch the config schema with UI hints.
    func configSchema() async throws -> ConfigSchemaResult {
        let response = try await send(method: GatewayMethod.configSchema)
        guard response.ok, let payload = response.payload else {
            throw GatewayClientError.requestFailed(response.error ?? ErrorShape(code: nil, message: "Unknown error", details: nil, retryable: nil, retryAfterMs: nil))
        }
        return try payload.decode(ConfigSchemaResult.self)
    }

    /// Fetch the list of available models from the gateway.
    func modelsList() async throws -> ModelsListResult {
        let response = try await send(method: GatewayMethod.modelsList)
        guard response.ok, let payload = response.payload else {
            throw GatewayClientError.requestFailed(response.error ?? ErrorShape(code: nil, message: "Unknown error", details: nil, retryable: nil, retryAfterMs: nil))
        }
        return try payload.decode(ModelsListResult.self)
    }

    /// Patch the gateway config (merge partial update).
    func configPatch(raw: String, baseHash: String, sessionKey: String? = nil, note: String? = nil) async throws {
        let params = ConfigPatchParams(raw: raw, baseHash: baseHash, sessionKey: sessionKey, note: note)
        let response = try await send(method: GatewayMethod.configPatch, params: params)
        guard response.ok else {
            throw GatewayClientError.requestFailed(response.error ?? ErrorShape(code: nil, message: "Config patch failed", details: nil, retryable: nil, retryAfterMs: nil))
        }
    }

    // MARK: - Private: Handshake

    private func performHandshake() async throws {
        guard let ws = webSocketTask else {
            throw GatewayClientError.notConnected
        }

        // Step 1: Receive connect.challenge from the WebSocket.
        // Performed directly on the actor (no separate Task) to avoid scheduling delay.
        let challengeData = try await receiveData(from: ws)
        let challengeFrame = try GatewayFrameDecoder.decode(from: challengeData)

        guard case .event(let event) = challengeFrame,
              event.event == GatewayEvent.connectChallenge else {
            throw GatewayClientError.handshakeFailed("Expected connect.challenge, got unexpected frame")
        }

        // Step 2: Send connect request
        let connectParams = ConnectParams(
            minProtocol: GatewayProtocol.version,
            maxProtocol: GatewayProtocol.version,
            client: .init(
                id: GatewayProtocol.clientName,
                version: GatewayProtocol.clientVersion,
                platform: GatewayProtocol.clientPlatform,
                mode: GatewayProtocol.clientMode
            ),
            role: GatewayProtocol.role,
            scopes: GatewayProtocol.scopes,
            auth: profile.token.map { ConnectParams.AuthInfo(token: $0, password: nil) },
            device: nil,
            locale: nil,
            userAgent: nil
        )

        let requestId = UUID().uuidString
        let paramsData = try JSONEncoder().encode(connectParams)
        let paramsJSON = try JSONSerialization.jsonObject(with: paramsData)
        let frame = RequestFrame(id: requestId, method: GatewayMethod.connect, params: AnyCodable(paramsJSON))
        try await sendFrame(frame)

        // Step 3: Receive hello-ok response
        let responseData = try await receiveData(from: ws)
        let responseFrame = try GatewayFrameDecoder.decode(from: responseData)

        guard case .response(let response) = responseFrame else {
            throw GatewayClientError.handshakeFailed("Expected hello-ok response, got unexpected frame")
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

    /// Extract raw data from a WebSocket message.
    private func receiveData(from ws: URLSessionWebSocketTask) async throws -> Data {
        let message = try await ws.receive()
        switch message {
        case .data(let d):
            return d
        case .string(let s):
            guard let d = s.data(using: .utf8) else {
                throw GatewayClientError.encodingError("Invalid UTF-8 in WebSocket message")
            }
            return d
        @unknown default:
            throw GatewayClientError.encodingError("Unknown WebSocket message type")
        }
    }

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
                // Always clean up pending continuations to prevent leaks
                cancelAllPendingRequests()

                // Only trigger reconnection if we were previously connected.
                // During handshake, connect() handles the failure itself.
                if !Task.isCancelled && isHandshakeComplete {
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
        // Forward events to the stream for UI consumption.
        // connect.challenge is handled directly in performHandshake().
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

    private var isReconnecting = false

    private func handleDisconnection() async {
        isHandshakeComplete = false

        // Prevent concurrent reconnection loops
        guard !isReconnecting else { return }

        guard shouldReconnect else {
            await setState(.disconnected)
            return
        }

        isReconnecting = true
        defer { isReconnecting = false }

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
    }

    // MARK: - Private: State management

    @MainActor
    private func setState(_ newState: ConnectionState) {
        let oldState = state
        state = newState
        if oldState != newState {
            stateChangeHandler?(newState)
        }
    }

}
