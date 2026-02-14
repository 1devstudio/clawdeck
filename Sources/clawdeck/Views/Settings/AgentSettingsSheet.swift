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

            if viewModel.isLoading {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading settings…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                Form {
                    agentIdentitySection
                    iconSection
                    gatewayConnectionSection
                    modelSection

                    if let errorMessage = viewModel.errorMessage {
                        errorSection(errorMessage)
                    }

                    if let successMessage = viewModel.successMessage {
                        successSection(successMessage)
                    }
                }
                .formStyle(.grouped)
            }

            Divider()

            // Footer buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.restartPhase != .none)

                Spacer()

                if viewModel.isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }

                Button("Save") {
                    Task {
                        let saved = await viewModel.saveChanges()
                        if saved {
                            // Apply accent color to the app immediately
                            appViewModel.applyAccentColor(viewModel.agentAccentColor)
                            
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
                .disabled(viewModel.isSaving || viewModel.restartPhase != .none)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 500, height: 620)
        .overlay {
            if viewModel.restartPhase != .none && viewModel.restartPhase != .done {
                GatewayRestartOverlay(phase: viewModel.restartPhase)
            }
        }
        .task {
            await viewModel.loadConfig()
        }
    }

    // MARK: - Sections

    private var agentIdentitySection: some View {
        Section("Agent Identity") {
            HStack {
                Label("Display Name", systemImage: "person.crop.circle")
                    .frame(width: 130, alignment: .leading)
                TextField("", text: $viewModel.agentDisplayName, prompt: Text("Agent Name"))
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.vertical, 2)

            HStack {
                Label("Emoji", systemImage: "face.smiling")
                    .frame(width: 130, alignment: .leading)
                TextField("", text: $viewModel.agentEmoji, prompt: Text("🤖"))
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

    private var iconSection: some View {
        Section("Rail Icon") {
            HStack(alignment: .top) {
                Label("Icon", systemImage: "star.square")
                    .frame(width: 130, alignment: .leading)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    // Current selection preview
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(viewModel.agentAccentColor.opacity(0.2))
                                .frame(width: 40, height: 40)

                            if let icon = viewModel.selectedIcon {
                                Image(systemName: icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(viewModel.agentAccentColor)
                            } else {
                                Text(String(viewModel.agentDisplayName.prefix(2)).uppercased())
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(viewModel.agentAccentColor)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.selectedIcon ?? "Initials")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if viewModel.selectedIcon != nil {
                                Button("Clear") {
                                    viewModel.selectedIcon = nil
                                }
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                            }
                        }
                    }

                    // Icon grid
                    IconPickerGrid(
                        selectedIcon: $viewModel.selectedIcon,
                        accentColor: viewModel.agentAccentColor
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var gatewayConnectionSection: some View {
        Section("Gateway Connection") {
            HStack {
                Label("Display Name", systemImage: "network")
                    .frame(width: 130, alignment: .leading)
                TextField("", text: $viewModel.gatewayDisplayName, prompt: Text("Gateway Name"))
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.vertical, 2)

            HStack {
                Label("Host", systemImage: "server.rack")
                    .frame(width: 130, alignment: .leading)
                TextField("", text: $viewModel.gatewayHost, prompt: Text("host.example.com"))
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.vertical, 2)

            HStack {
                Label("Port", systemImage: "number")
                    .frame(width: 130, alignment: .leading)
                TextField("", text: $viewModel.gatewayPort, prompt: Text("443"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)

                Spacer()

                Text("TLS")
                    .font(.body)
                Toggle("", isOn: $viewModel.gatewayUseTLS)
                    .labelsHidden()
            }
            .padding(.vertical, 2)

            HStack {
                Label("Token", systemImage: "key")
                    .frame(width: 130, alignment: .leading)
                SecureField("", text: $viewModel.gatewayToken, prompt: Text("Access Token"))
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
                TextField("", text: $viewModel.primaryModel, prompt: Text("anthropic/claude-3-sonnet"))
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

// MARK: - Gateway Restart Overlay

/// Full-sheet overlay shown while the gateway restarts after a config change.
struct GatewayRestartOverlay: View {
    let phase: AgentSettingsViewModel.RestartPhase

    private var statusText: String {
        switch phase {
        case .applyingConfig: return "Applying configuration…"
        case .waitingForRestart: return "Gateway is restarting…"
        case .reconnecting: return "Reconnecting…"
        case .done, .none: return ""
        }
    }

    private var detailText: String {
        switch phase {
        case .applyingConfig: return "Sending changes to the gateway"
        case .waitingForRestart: return "Waiting for the gateway to come back online"
        case .reconnecting: return "Re-establishing connection"
        case .done, .none: return ""
        }
    }

    /// Progress value (0–1) for the determinate indicator.
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
            // Dimmed background
            Rectangle()
                .fill(.ultraThinMaterial)

            VStack(spacing: 16) {
                // Animated icon
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(phase == .waitingForRestart ? 360 : 0))
                    .animation(
                        phase == .waitingForRestart
                            ? .linear(duration: 2).repeatForever(autoreverses: false)
                            : .default,
                        value: phase
                    )

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

// MARK: - Icon Picker Grid

/// Compact grid of common SF Symbols for selecting an agent rail icon.
struct IconPickerGrid: View {
    @Binding var selectedIcon: String?
    let accentColor: Color

    /// Curated set of icons suitable for agent avatars.
    private let icons: [String] = [
        // Robots & AI
        "cpu", "brain", "desktopcomputer", "terminal",
        // Characters
        "person.fill", "figure.stand", "face.smiling", "theatermasks",
        // Nature & objects
        "bolt.fill", "star.fill", "heart.fill", "flame.fill",
        "leaf.fill", "drop.fill", "moon.fill", "sun.max.fill",
        // Tech
        "antenna.radiowaves.left.and.right", "network", "globe", "command",
        // Animals & fun
        "hare.fill", "tortoise.fill", "bird.fill", "ant.fill",
        // Abstract
        "hexagon.fill", "diamond.fill", "circle.grid.cross.fill", "sparkle",
    ]

    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 6), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(icons, id: \.self) { icon in
                Button {
                    selectedIcon = icon
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(selectedIcon == icon ? .white : .secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedIcon == icon ? accentColor : Color.gray.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .help(icon)
            }
        }
    }
}
