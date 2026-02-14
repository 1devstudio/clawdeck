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
            HStack(alignment: .top) {
                Label("Primary Model", systemImage: "brain")
                    .frame(width: 130, alignment: .leading)
                    .padding(.top, 4)
                Spacer(minLength: 8)
                ModelPicker(
                    selectedModel: $viewModel.primaryModel,
                    client: appViewModel.activeClient
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
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

// MARK: - Model Picker (Autocomplete)

/// A model entry with its qualified ID for display and selection.
struct ModelOption: Identifiable {
    let qualifiedId: String   // "provider/model-id"
    let displayName: String   // "Claude Opus 4.6"
    let provider: String      // "anthropic"
    var id: String { qualifiedId }
}

/// Autocomplete model picker that fetches from the gateway via `models.list`.
/// Type to filter by model name or provider/id; click a suggestion to select.
/// Uses `.popover()` so the dropdown escapes Form clipping on macOS.
struct ModelPicker: View {
    @Binding var selectedModel: String
    let client: GatewayClient?

    @State private var allModels: [ModelOption] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var showPopover = false
    @State private var hoveredId: String?

    /// Friendly name for the currently selected model, if known.
    private var displayName: String? {
        allModels.first(where: { $0.qualifiedId == selectedModel })?.displayName
    }

    /// Filtered suggestions based on search text.
    private var suggestions: [ModelOption] {
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            return Array(allModels.prefix(50))
        }
        return allModels.filter { model in
            model.displayName.lowercased().contains(query) ||
            model.qualifiedId.lowercased().contains(query) ||
            model.provider.lowercased().contains(query)
        }
    }

    /// Suggestions grouped by provider.
    private var groupedSuggestions: [(provider: String, models: [ModelOption])] {
        var grouped: [String: [ModelOption]] = [:]
        for model in suggestions {
            grouped[model.provider, default: []].append(model)
        }
        return grouped.sorted { $0.key < $1.key }.map { (provider: $0.key, models: $0.value) }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            // Clickable field that opens the popover
            Button {
                searchText = ""
                showPopover = true
            } label: {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text(displayName ?? (selectedModel.isEmpty ? "Select model…" : selectedModel))
                        .font(.system(size: 12))
                        .foregroundStyle(selectedModel.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                modelSearchPopover
            }

            // Qualified ID subtitle
            if !selectedModel.isEmpty && displayName != nil {
                Text(selectedModel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .task {
            await loadModels()
        }
    }

    // MARK: - Search Popover

    private var modelSearchPopover: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("", text: $searchText, prompt: Text("Search models…"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // Results
            if suggestions.isEmpty {
                VStack(spacing: 4) {
                    Text("No models match \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groupedSuggestions, id: \.provider) { group in
                            // Provider header
                            Text(group.provider.capitalized)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                                .padding(.bottom, 2)

                            ForEach(group.models) { model in
                                Button {
                                    selectedModel = model.qualifiedId
                                    showPopover = false
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(model.displayName)
                                                .font(.system(size: 12))
                                                .foregroundStyle(.primary)
                                            Text(model.qualifiedId)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.tertiary)
                                        }
                                        Spacer()
                                        if model.qualifiedId == selectedModel {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(hoveredId == model.qualifiedId ? Color.blue.opacity(0.1) : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .onHover { isHovered in
                                    hoveredId = isHovered ? model.qualifiedId : nil
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if suggestions.isEmpty {
                    Text("No models match \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }
        }
        .frame(width: 300)
        .frame(maxHeight: 250)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .zIndex(100)
    }

    // MARK: - Data Loading

    private func loadModels() async {
        guard let client else {
            isLoading = false
            return
        }

        do {
            let result = try await client.modelsList()
            allModels = result.models
                .map { ModelOption(qualifiedId: "\($0.provider)/\($0.id)", displayName: $0.name, provider: $0.provider) }
                .sorted { $0.displayName < $1.displayName }
        } catch {
            print("[ModelPicker] Failed to load models: \(error)")
        }

        isLoading = false
    }
}
