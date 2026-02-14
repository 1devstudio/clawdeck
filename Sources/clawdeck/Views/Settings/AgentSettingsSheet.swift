import SwiftUI

/// Settings sheet for configuring agent identity, gateway connection, and model settings.
struct AgentSettingsSheet: View {
    let appViewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var viewModel: AgentSettingsViewModel
    
    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
        self._viewModel = State(initialValue: AgentSettingsViewModel(appViewModel: appViewModel))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Agent Settings")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            Form {
                if viewModel.isLoading {
                    loadingSection
                } else {
                    agentIdentitySection
                    gatewayConnectionSection
                    modelSection

                    if let errorMessage = viewModel.errorMessage {
                        errorSection(errorMessage)
                    }

                    if let successMessage = viewModel.successMessage {
                        successSection(successMessage)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if viewModel.isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }

                Button("Save") {
                    Task {
                        await viewModel.saveChanges()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 500, height: 550)
        .task {
            await viewModel.loadConfig()
        }
    }
    
    // MARK: - Sections
    
    private var loadingSection: some View {
        Section {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading settings...")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }
    
    private var agentIdentitySection: some View {
        Section("Agent Identity") {
            HStack {
                Label("Display Name", systemImage: "person.crop.circle")
                    .frame(width: 130, alignment: .leading)
                TextField("Agent Name", text: $viewModel.agentDisplayName)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.vertical, 2)
            
            HStack {
                Label("Emoji", systemImage: "face.smiling")
                    .frame(width: 130, alignment: .leading)
                TextField("🤖", text: $viewModel.agentEmoji)
                    .textFieldStyle(.roundedBorder)
                    .help("Emoji avatar for the agent")
            }
            .padding(.vertical, 2)
            
            HStack {
                Label("Accent Color", systemImage: "paintpalette")
                    .frame(width: 130, alignment: .leading)
                ColorPicker("", selection: $viewModel.agentAccentColor, supportsOpacity: false)
                    .labelsHidden()
                Spacer()
            }
            .padding(.vertical, 2)
        }
    }
    
    private var gatewayConnectionSection: some View {
        Section("Gateway Connection") {
            HStack {
                Label("Display Name", systemImage: "network")
                    .frame(width: 130, alignment: .leading)
                TextField("Gateway Name", text: $viewModel.gatewayDisplayName)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.vertical, 2)
            
            HStack {
                Label("Host", systemImage: "server.rack")
                    .frame(width: 130, alignment: .leading)
                TextField("host.example.com", text: $viewModel.gatewayHost)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.vertical, 2)
            
            HStack {
                Label("Port", systemImage: "number")
                    .frame(width: 130, alignment: .leading)
                TextField("443", text: $viewModel.gatewayPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                
                Spacer()
                
                Toggle("Use TLS", isOn: $viewModel.gatewayUseTLS)
            }
            .padding(.vertical, 2)
            
            HStack {
                Label("Token", systemImage: "key")
                    .frame(width: 130, alignment: .leading)
                SecureField("Access Token", text: $viewModel.gatewayToken)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.vertical, 2)
        }
    }
    
    private var modelSection: some View {
        Section("Model Configuration") {
            HStack {
                Label("Primary Model", systemImage: "brain")
                    .frame(width: 130, alignment: .leading)
                TextField("anthropic/claude-3-sonnet", text: $viewModel.primaryModel)
                    .textFieldStyle(.roundedBorder)
                    .help("Default model for new conversations")
            }
            .padding(.vertical, 2)
        }
    }
    
    private func errorSection(_ message: String) -> some View {
        Section {
            Label {
                Text(message)
                    .foregroundStyle(.red)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }
    
    private func successSection(_ message: String) -> some View {
        Section {
            Label {
                Text(message)
                    .foregroundStyle(.green)
            } icon: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        }
    }
}

// Preview requires a live gateway connection, so omitted.