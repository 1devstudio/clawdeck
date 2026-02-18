import SwiftUI

/// Sheet for creating a new agent on a connected gateway.
struct CreateAgentSheet: View {
    let appViewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: CreateAgentViewModel

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
        self._viewModel = State(initialValue: CreateAgentViewModel(appViewModel: appViewModel))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create New Agent")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            Form {
                agentIdSection
                identitySection
                workspaceSection
                gatewaySection
                modelSection

                if let errorMessage = viewModel.errorMessage {
                    errorSection(errorMessage)
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.restartPhase != .none && viewModel.restartPhase != .done)

                Spacer()

                if viewModel.isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }

                Button("Create Agent") {
                    Task {
                        let success = await viewModel.createAgent()
                        if success {
                            // Brief pause so the user sees the "done" state
                            if viewModel.restartPhase == .done {
                                try? await Task.sleep(nanoseconds: 600_000_000)
                            }
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canSubmit)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 480, height: 520)
        .overlay {
            if viewModel.restartPhase != .none && viewModel.restartPhase != .done {
                CreateAgentRestartOverlay(phase: viewModel.restartPhase)
            }
        }
        .task {
            await viewModel.fetchConfigHash()
        }
    }

    // MARK: - Sections

    private var agentIdSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Agent ID", systemImage: "at")
                        .frame(width: 130, alignment: .leading)
                    TextField("", text: $viewModel.agentId, prompt: Text("my-agent"))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onChange(of: viewModel.agentId) { _, newValue in
                            // Auto-lowercase as the user types
                            let lowered = newValue.lowercased()
                            if lowered != newValue {
                                viewModel.agentId = lowered
                            }
                        }
                }

                if let validation = viewModel.agentIdValidationMessage {
                    Text(validation)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.leading, 134)
                } else if viewModel.isAgentIdValid && !viewModel.isAgentIdConflicting {
                    Text("✓ Available")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.leading, 134)
                }
            }
        } header: {
            Text("Agent ID")
        } footer: {
            Text("Unique identifier for the agent. Used in session keys and file paths.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var identitySection: some View {
        Section("Identity") {
            HStack {
                Label("Display Name", systemImage: "person.crop.circle")
                    .frame(width: 130, alignment: .leading)
                TextField("", text: $viewModel.displayName, prompt: Text("My Agent"))
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.vertical, 2)

            HStack {
                Label("Emoji", systemImage: "face.smiling")
                    .frame(width: 130, alignment: .leading)
                TextField("", text: $viewModel.emoji, prompt: Text("🤖"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Spacer()
            }
            .padding(.vertical, 2)
        }
    }

    private var workspaceSection: some View {
        Section {
            HStack {
                Label("Path", systemImage: "folder")
                    .frame(width: 130, alignment: .leading)
                TextField("", text: $viewModel.workspace, prompt: Text(viewModel.defaultWorkspace))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
            .padding(.vertical, 2)
        } header: {
            Text("Workspace")
        } footer: {
            Text("Working directory on the gateway host. Created automatically if it doesn't exist.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var gatewaySection: some View {
        Section("Gateway") {
            HStack {
                Label("Target", systemImage: "server.rack")
                    .frame(width: 130, alignment: .leading)

                if appViewModel.gatewayManager.gatewayProfiles.count == 1 {
                    // Single gateway — just show the name
                    let profile = appViewModel.gatewayManager.gatewayProfiles[0]
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appViewModel.gatewayManager.isConnected(profile.id) ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(profile.displayName)
                            .foregroundStyle(.primary)
                        Text(profile.displayAddress)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    // Multiple gateways — picker
                    Picker("", selection: $viewModel.targetGatewayId) {
                        ForEach(appViewModel.gatewayManager.gatewayProfiles) { profile in
                            HStack {
                                Circle()
                                    .fill(appViewModel.gatewayManager.isConnected(profile.id) ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(profile.displayName)
                            }
                            .tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: viewModel.targetGatewayId) { _, _ in
                        viewModel.loadExistingAgents()
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var modelSection: some View {
        Section {
            HStack(alignment: .top) {
                Label("Primary Model", systemImage: "brain")
                    .frame(width: 130, alignment: .leading)
                    .padding(.top, 4)
                Spacer(minLength: 8)
                ModelPicker(
                    selectedModel: $viewModel.selectedModel,
                    client: appViewModel.gatewayManager.client(for: viewModel.targetGatewayId)
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Model")
        } footer: {
            Text("Optional. Leave empty to inherit the gateway default.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
}

// MARK: - Restart Overlay

/// Overlay shown during agent creation (config patch → restart → reconnect).
struct CreateAgentRestartOverlay: View {
    let phase: CreateAgentViewModel.RestartPhase

    private var statusText: String {
        switch phase {
        case .applyingConfig: return "Creating agent…"
        case .waitingForRestart: return "Gateway is restarting…"
        case .reconnecting: return "Reconnecting…"
        case .done, .none: return ""
        }
    }

    private var detailText: String {
        switch phase {
        case .applyingConfig: return "Sending agent configuration to the gateway"
        case .waitingForRestart: return "Waiting for the gateway to come back online"
        case .reconnecting: return "Re-establishing connection and loading agents"
        case .done, .none: return ""
        }
    }

    private var progress: Double {
        switch phase {
        case .none: return 0
        case .applyingConfig: return 0.2
        case .waitingForRestart: return 0.5
        case .reconnecting: return 0.8
        case .done: return 1.0
        }
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            VStack(spacing: 16) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, isActive: phase == .waitingForRestart)

                Text(statusText)
                    .font(.headline)

                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .animation(.easeInOut(duration: 0.5), value: progress)
            }
            .padding(32)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            }
        }
    }
}
