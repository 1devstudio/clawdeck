import SwiftUI

/// Gateway connection wizard — used for first-run onboarding and "Connect New Gateway" sheet.
struct ConnectionSetupView: View {
    let appViewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var gatewayName = ""
    @State private var host = ""
    @State private var port = "18789"
    @State private var token = ""
    @State private var useTLS = false
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
                Button("Cancel") {
                    appViewModel.showConnectionSetup = false
                    appViewModel.showGatewayConnectionSheet = false
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 8)
                }

                Button("Connect") {
                    Task { await connect() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.isEmpty || port.isEmpty || isConnecting)
                .keyboardShortcut(.defaultAction)
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
                
                // Switch to the newly added agent
                await appViewModel.switchAgent(binding)
                
                appViewModel.showConnectionSetup = false
                appViewModel.showGatewayConnectionSheet = false
                dismiss()
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
                await appViewModel.switchAgent(binding)
                
                appViewModel.showConnectionSetup = false
                appViewModel.showGatewayConnectionSheet = false
                dismiss()
            } else {
                errorMessage = "No agents found on this gateway"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isConnecting = false
    }
}
