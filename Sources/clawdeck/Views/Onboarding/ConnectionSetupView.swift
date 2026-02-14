import SwiftUI

/// First-run gateway connection wizard shown when no gateways are configured.
struct ConnectionSetupView: View {
    let appViewModel: AppViewModel

    @State private var gatewayName = ""
    @State private var host = "vps-0a60f62f.vps.ovh.net"
    @State private var port = "443"
    @State private var token = ""
    @State private var useTLS = true
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                Text("Connect to Gateway")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Enter your Clawdbot gateway details to connect.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Fields
            VStack(spacing: 16) {
                LabeledContent("Gateway Name") {
                    TextField("e.g. Main Gateway", text: $gatewayName)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Host") {
                    TextField("Host", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                }
                
                LabeledContent("Port") {
                    TextField("Port", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                
                Toggle("Use TLS (wss://)", isOn: $useTLS)

                LabeledContent("Token") {
                    SecureField("Gateway Token (optional)", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 8)

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
                Button("Skip") {
                    appViewModel.showConnectionSetup = false
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Connect") {
                    Task { await connect() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.isEmpty || port.isEmpty || isConnecting)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 420, height: 400)
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil

        guard let portNumber = Int(port) else {
            errorMessage = "Invalid port number"
            isConnecting = false
            return
        }

        do {
            // Test the connection and get agent list
            let agentsResult = try await appViewModel.gatewayManager.testConnection(
                host: host,
                port: portNumber,
                path: "/ws",
                useTLS: useTLS,
                token: token.isEmpty ? nil : token
            )

            // Connection successful - add the gateway profile
            let profile = GatewayProfile(
                displayName: gatewayName.isEmpty ? host : gatewayName,
                host: host,
                port: portNumber,
                path: "/ws",
                useTLS: useTLS,
                token: token.isEmpty ? nil : token
            )

            appViewModel.gatewayManager.addGatewayProfile(profile)

            // Auto-add the default agent as a binding
            if let defaultAgentId = agentsResult.defaultId,
               let defaultAgent = agentsResult.agents.first(where: { $0.id == defaultAgentId }) {
                let binding = AgentBinding(
                    gatewayId: profile.id,
                    agentId: defaultAgent.id,
                    localDisplayName: defaultAgent.name,
                    railOrder: 1
                )
                appViewModel.gatewayManager.addAgentBinding(binding)
                
                // Connect to all gateways and load data
                await appViewModel.connectAndLoad()
                
                appViewModel.showConnectionSetup = false
            } else if let firstAgent = agentsResult.agents.first {
                // Fallback to first agent
                let binding = AgentBinding(
                    gatewayId: profile.id,
                    agentId: firstAgent.id,
                    localDisplayName: firstAgent.name,
                    railOrder: 1
                )
                appViewModel.gatewayManager.addAgentBinding(binding)
                
                await appViewModel.connectAndLoad()
                appViewModel.showConnectionSetup = false
            } else {
                errorMessage = "No agents found on this gateway"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isConnecting = false
    }
}
