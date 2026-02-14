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
                        let saved = await viewModel.saveChanges()
                        if saved {
                            // Apply accent color to the app immediately
                            appViewModel.applyAccentColor(viewModel.agentAccentColor)
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isSaving)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 500, height: 620)
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
