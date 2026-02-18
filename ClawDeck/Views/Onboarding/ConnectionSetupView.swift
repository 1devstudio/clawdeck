import SwiftUI

// MARK: - Wizard Phase

/// The three phases of the connection wizard.
private enum WizardPhase: Equatable {
    /// Probing localhost for a running gateway.
    case autoDetecting
    /// A local gateway was found — ask user to confirm.
    case localFound
    /// Manual entry form (no local gateway, or user chose "Connect Another").
    case manualEntry
}

/// Gateway connection wizard — used for first-run onboarding and "Connect New Gateway" sheet.
///
/// Flow:
/// 1. **Auto-detect** — probe localhost for a running gateway (~3s).
/// 2. **Local found** — show confirmation: "Connect" or "Connect to Another".
/// 3. **Manual entry** — host + token, with smart auto-probing and collapsed Advanced section.
struct ConnectionSetupView: View {
    let appViewModel: AppViewModel

    /// When true, skip auto-detect and go straight to manual entry.
    /// Set when the user opens "Connect New Gateway" from settings (they already have a connection).
    var skipAutoDetect: Bool = false

    @Environment(\.themeColor) private var themeColor
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var phase: WizardPhase = .autoDetecting

    /// Auto-detect result (kept so the "Local found" screen can use it).
    @State private var localProbeResult: GatewayProber.ProbeResult?

    // Manual entry fields
    @State private var host = ""
    @State private var token = ""

    // Advanced (collapsed by default)
    @State private var showAdvanced = false
    @State private var advancedPort = ""
    @State private var advancedUseTLS = false

    // Connection state
    @State private var isConnecting = false
    @State private var probeStatus = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .autoDetecting:
                autoDetectingView
            case .localFound:
                localFoundView
            case .manualEntry:
                manualEntryView
            }
        }
        .frame(width: 420, height: phase == .autoDetecting ? 200 : 420)
        .animation(.easeInOut(duration: 0.2), value: phase)
        .task {
            if skipAutoDetect {
                phase = .manualEntry
            } else {
                await runAutoDetect()
            }
        }
    }

    // MARK: - Phase 1: Auto-detecting

    private var autoDetectingView: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .controlSize(.regular)

            Text("Looking for gateway…")
                .font(.title3)
                .fontWeight(.medium)

            Text("Checking localhost")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Let impatient users skip
            Button("Skip") {
                phase = .manualEntry
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Phase 2: Local gateway found

    private var localFoundView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text("Local Gateway Found")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let result = localProbeResult {
                    Text("Clawdbot is running on this Mac")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Text("localhost:\(result.port)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if result.agents.agents.count > 0 {
                        let names = result.agents.agents.prefix(3).map(\.name).joined(separator: ", ")
                        let suffix = result.agents.agents.count > 3 ? " + \(result.agents.agents.count - 3) more" : ""
                        Text("Agents: \(names)\(suffix)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            HStack {
                Button("Connect to Another") {
                    phase = .manualEntry
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Connect") {
                    Task { await connectWithProbeResult(localProbeResult!) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Phase 3: Manual entry

    private var manualEntryView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 48))
                    .foregroundStyle(themeColor)

                Text("Connect to Gateway")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Enter your gateway host and token.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Fields
            VStack(spacing: 16) {
                LabeledContent("Host or IP") {
                    TextField("gateway.example.com or 192.168.1.50", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                        .onSubmit { Task { await connectRemote() } }
                }

                LabeledContent("Token") {
                    SecureField("Gateway auth token", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .onSubmit { Task { await connectRemote() } }
                }

                // Advanced — collapsed by default
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    VStack(spacing: 12) {
                        LabeledContent("Port") {
                            TextField("Auto", text: $advancedPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }

                        Toggle("Use TLS (wss://)", isOn: $advancedUseTLS)
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 8)

            // Probe status
            if !probeStatus.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(probeStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
            }

            // Error
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            // Actions
            HStack {
                Button("Cancel") {
                    appViewModel.showConnectionSetup = false
                    appViewModel.showGatewayConnectionSheet = false
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Connect") {
                    Task { await connectRemote() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Logic

    /// Phase 1: Try to find a local gateway.
    private func runAutoDetect() async {
        // Skip auto-detect if we came back to this view from elsewhere
        guard phase == .autoDetecting else { return }

        let prober = GatewayProber()
        if let result = await prober.probeLocal() {
            localProbeResult = result
            phase = .localFound
        } else {
            phase = .manualEntry
        }
    }

    /// Phase 3: Connect to a remote gateway (with smart probing or direct).
    private func connectRemote() async {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty else { return }

        isConnecting = true
        errorMessage = nil
        probeStatus = ""

        let prober = GatewayProber()
        let resolvedToken = token.isEmpty ? nil : token

        // If Advanced is open with explicit values → direct probe
        if showAdvanced, let port = Int(advancedPort), !advancedPort.isEmpty {
            probeStatus = "Connecting to \(GatewayProber.probeDescription(host: trimmedHost, port: port, useTLS: advancedUseTLS))…"

            if let result = await prober.probeDirect(host: trimmedHost, port: port, useTLS: advancedUseTLS, token: resolvedToken) {
                await connectWithProbeResult(result)
                return
            }

            errorMessage = "Could not connect to \(trimmedHost):\(port)"
            probeStatus = ""
            isConnecting = false
            return
        }

        // Smart probing — try multiple endpoints
        // Show progress for each attempt
        let candidates: [(Int, Bool)]
        if isPrivateOrLocal(trimmedHost) {
            candidates = [(18789, false), (443, true), (80, false)]
        } else {
            candidates = [(443, true), (8443, true), (18789, false)]
        }

        for (port, tls) in candidates {
            probeStatus = "Trying \(GatewayProber.probeDescription(host: trimmedHost, port: port, useTLS: tls))…"

            if let result = await prober.probeDirect(host: trimmedHost, port: port, useTLS: tls, token: resolvedToken) {
                await connectWithProbeResult(result)
                return
            }
        }

        errorMessage = "Could not connect to \(trimmedHost). Check the host and token, or use Advanced to specify port and TLS."
        probeStatus = ""
        isConnecting = false
    }

    /// Save profile, add default agent binding, connect, and dismiss.
    private func connectWithProbeResult(_ result: GatewayProber.ProbeResult) async {
        isConnecting = true
        probeStatus = ""

        let displayName = result.host == "localhost" ? "Local" : result.host
        let profile = GatewayProfile(
            displayName: displayName,
            host: result.host,
            port: result.port,
            path: "",
            useTLS: result.useTLS,
            token: result.token
        )

        appViewModel.gatewayManager.addGatewayProfile(profile)

        // Pick the default agent, or the first one
        let agent: AgentSummary? = {
            if let defaultId = result.agents.defaultId {
                return result.agents.agents.first { $0.id == defaultId }
            }
            return result.agents.agents.first
        }()

        if let agent {
            let binding = AgentBinding(
                gatewayId: profile.id,
                agentId: agent.id,
                localDisplayName: agent.name,
                railOrder: 1
            )
            appViewModel.gatewayManager.addAgentBinding(binding)

            await appViewModel.connectAndLoad()
            await appViewModel.switchAgent(binding)

            appViewModel.showConnectionSetup = false
            appViewModel.showGatewayConnectionSheet = false
            dismiss()
        } else {
            errorMessage = "No agents found on this gateway"
            isConnecting = false
        }
    }

    // MARK: - Helpers

    /// Mirror of GatewayProber's private IP check (view-side, for probe ordering).
    private func isPrivateOrLocal(_ host: String) -> Bool {
        if host.hasSuffix(".local") { return true }
        if !host.contains(".") { return true }
        if host.hasPrefix("192.168.") || host.hasPrefix("10.") { return true }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        if host == "127.0.0.1" || host == "::1" || host == "localhost" { return true }
        return false
    }
}
