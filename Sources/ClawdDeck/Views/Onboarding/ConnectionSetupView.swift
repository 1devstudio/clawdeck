import SwiftUI

/// First-run connection wizard shown when no profiles are configured.
struct ConnectionSetupView: View {
    let appViewModel: AppViewModel

    @State private var displayName = "My Agent"
    @State private var host = "vps-0a60f62f.vps.ovh.net"
    @State private var port = "443"
    @State private var token = ""
    @State private var useTLS = false
    @State private var selectedAvatar = "sf:robot"
    @State private var isConnecting = false
    @State private var errorMessage: String?

    private let builtInAvatars = [
        "robot", "desktopcomputer", "brain.head.profile", "cpu",
        "cloud", "server.rack", "antenna.radiowaves.left.and.right",
        "globe", "bolt.circle", "wand.and.stars", "sparkles",
        "terminal", "chevron.left.forwardslash.chevron.right",
        "gearshape", "atom"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                // Live avatar preview
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 64, height: 64)

                    if selectedAvatar.hasPrefix("sf:") {
                        Image(systemName: String(selectedAvatar.dropFirst(3)))
                            .font(.system(size: 28))
                            .foregroundStyle(.accentColor)
                    }
                }

                Text("Set Up Your Agent")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Give your agent a name, pick an avatar, and connect to your gateway.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Fields
            ScrollView {
                VStack(spacing: 16) {
                    LabeledContent("Name") {
                        TextField("Agent Name", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Avatar grid
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Avatar")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 8), spacing: 6) {
                            ForEach(builtInAvatars, id: \.self) { symbol in
                                let key = "sf:\(symbol)"
                                Button {
                                    selectedAvatar = key
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedAvatar == key ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                                            .frame(width: 40, height: 40)
                                        Image(systemName: symbol)
                                            .font(.system(size: 16))
                                            .foregroundStyle(selectedAvatar == key ? Color.accentColor : Color.secondary)
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedAvatar == key ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider()

                    // Connection
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
            }

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
        .frame(width: 460, height: 600)
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil

        guard let portNumber = Int(port) else {
            errorMessage = "Invalid port number"
            isConnecting = false
            return
        }

        let name = displayName.isEmpty ? "My Agent" : displayName
        let profile = ConnectionProfile(
            name: name,
            displayName: name,
            host: host,
            port: portNumber,
            useTLS: useTLS,
            token: token.isEmpty ? nil : token,
            isDefault: true,
            avatarName: selectedAvatar
        )

        appViewModel.connectionManager.addProfile(profile)
        await appViewModel.connect(with: profile)

        if appViewModel.connectionManager.isConnected {
            appViewModel.showConnectionSetup = false
        } else {
            errorMessage = appViewModel.connectionManager.lastError ?? "Failed to connect"
        }

        isConnecting = false
    }
}
