import SwiftUI

/// First-run connection wizard shown when no profiles are configured.
struct ConnectionSetupView: View {
    let appViewModel: AppViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var name = "Default"
    @State private var host = "vps-0a60f62f.vps.ovh.net"
    @State private var port = "443"
    @State private var token = ""
    @State private var useTLS = false
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)

                Text("Connect to Gateway")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Enter the address and token for your Clawdbot gateway.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Form
            Form {
                Section {
                    TextField("Connection Name", text: $name)
                    TextField("Host", text: $host)
                        .textContentType(.URL)
                    TextField("Port", text: $port)
                    Toggle("Use TLS (wss://)", isOn: $useTLS)
                }

                Section("Authentication") {
                    SecureField("Gateway Token (optional)", text: $token)
                        .textContentType(.password)
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 280)

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
                    dismiss()
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
        .frame(width: 440, height: 520)
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil

        guard let portNumber = Int(port) else {
            errorMessage = "Invalid port number"
            isConnecting = false
            return
        }

        let profile = ConnectionProfile(
            name: name.isEmpty ? "Default" : name,
            host: host,
            port: portNumber,
            useTLS: useTLS,
            token: token.isEmpty ? nil : token,
            isDefault: true
        )

        appViewModel.connectionManager.addProfile(profile)
        await appViewModel.connect(with: profile)

        if appViewModel.connectionManager.isConnected {
            dismiss()
        } else {
            errorMessage = appViewModel.connectionManager.lastError ?? "Failed to connect"
        }

        isConnecting = false
    }
}
