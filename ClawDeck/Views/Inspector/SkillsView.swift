import SwiftUI

/// Skills list view — displayed as a tab in the Inspector panel.
struct SkillsView: View {
    @Bindable var viewModel: SkillsViewModel
    var useGroupedStyle: Bool = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.skills.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.skills.isEmpty {
                errorView(error)
            } else if viewModel.skills.isEmpty {
                emptyView
            } else {
                if useGroupedStyle {
                    groupedSkillsList
                } else {
                    skillsList
                }
            }
        }
        .task {
            await viewModel.loadSkills()
        }
    }

    // MARK: - Skills list

    private var skillsList: some View {
        List {
            let grouped = viewModel.groupedSkills
            
            if !grouped.ready.isEmpty {
                Section {
                    ForEach(grouped.ready) { skill in
                        skillRow(for: skill)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Label("Ready (\(grouped.ready.count))", systemImage: "checkmark.circle")
                        Spacer()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                }
            }
            
            if !grouped.disabled.isEmpty {
                Section {
                    ForEach(grouped.disabled) { skill in
                        skillRow(for: skill)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Label("Disabled (\(grouped.disabled.count))", systemImage: "pause.circle")
                        Spacer()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                }
            }
            
            if !grouped.unavailable.isEmpty {
                Section {
                    ForEach(grouped.unavailable) { skill in
                        skillRow(for: skill)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Label("Unavailable (\(grouped.unavailable.count))", systemImage: "exclamationmark.triangle")
                        Spacer()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.loadSkills()
        }
    }
    
    private func skillRow(for skill: SkillInfo) -> some View {
        SkillRow(
            skill: skill,
            isExpanded: viewModel.expandedSkillKey == skill.key,
            isBusy: viewModel.busySkillKeys.contains(skill.key),
            editingApiKey: viewModel.editingApiKeyFor == skill.key,
            apiKeyText: $viewModel.apiKeyText,
            onToggleExpand: { viewModel.toggleExpanded(skill.key) },
            onToggleEnabled: { Task { await viewModel.toggleEnabled(skill) } },
            onEditApiKey: {
                viewModel.editingApiKeyFor = skill.key
                viewModel.apiKeyText = ""
            },
            onSaveApiKey: { Task { await viewModel.saveApiKey(for: skill.key) } },
            onCancelApiKey: { viewModel.editingApiKeyFor = nil }
        )
    }

    private var groupedSkillsList: some View {
        Form {
            let grouped = viewModel.groupedSkills

            if !grouped.ready.isEmpty {
                Section {
                    ForEach(grouped.ready) { skill in
                        skillRow(for: skill)
                    }
                } header: {
                    Label("Ready (\(grouped.ready.count))", systemImage: "checkmark.circle")
                }
            }

            if !grouped.disabled.isEmpty {
                Section {
                    ForEach(grouped.disabled) { skill in
                        skillRow(for: skill)
                    }
                } header: {
                    Label("Disabled (\(grouped.disabled.count))", systemImage: "pause.circle")
                }
            }
            
            if !grouped.unavailable.isEmpty {
                Section {
                    ForEach(grouped.unavailable) { skill in
                        skillRow(for: skill)
                    }
                } header: {
                    Label("Unavailable (\(grouped.unavailable.count))", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Loading skills…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.loadSkills() }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No Skills",
            systemImage: "puzzlepiece",
            description: Text("No skills found on this gateway.")
        )
    }
}

// MARK: - Skill Row

/// A single skill row with expandable details.
struct SkillRow: View {
    let skill: SkillInfo
    let isExpanded: Bool
    let isBusy: Bool
    let editingApiKey: Bool
    @Binding var apiKeyText: String
    var onToggleExpand: () -> Void
    var onToggleEnabled: () -> Void
    var onEditApiKey: () -> Void
    var onSaveApiKey: () -> Void
    var onCancelApiKey: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row — clickable to expand
            Button(action: onToggleExpand) {
                mainRow
            }
            .buttonStyle(.plain)

            // Expanded details
            if isExpanded {
                expandedDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    // MARK: - Main row

    private var mainRow: some View {
        HStack(spacing: 8) {
            // Status indicator
            statusIndicator

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(skill.enabled ? .primary : .secondary)
                    
                    // Source badge
                    if let source = skill.source {
                        Text(source)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.quaternary)
                            )
                    }
                }

                // Status line
                HStack(spacing: 6) {
                    if skill.isDisabledByUser {
                        Label("Disabled", systemImage: "pause.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if skill.blockedByAllowlist {
                        Label("Blocked", systemImage: "lock")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if skill.needsApiKey {
                        Label("API key required", systemImage: "key")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    } else if !skill.missingOs.isEmpty {
                        Label("Requires \(skill.missingOs.joined(separator: ", "))", systemImage: "desktopcomputer")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if skill.hasMissingDeps {
                        Label("Missing dependencies", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    } else if skill.isReady {
                        Label("Ready", systemImage: "checkmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            // Chevron
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var statusIndicator: some View {
        Group {
            if isBusy {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
            } else if !skill.enabled {
                Circle()
                    .fill(.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
            } else if skill.needsApiKey {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
            } else if skill.hasMissingDeps {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
            } else if skill.isReady {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .fill(.gray)
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: 16)
    }

    // MARK: - Expanded details

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.vertical, 4)

            // Description
            if let description = skill.description {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Description")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }

            // Info grid
            detailGrid

            // Missing dependencies
            if skill.hasMissingDeps {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Missing Dependencies")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    if !skill.missingBins.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Binaries:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.orange)
                            ForEach(skill.missingBins, id: \.self) { bin in
                                Text("• \(bin)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    if !skill.missingEnv.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Environment variables:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.orange)
                            ForEach(skill.missingEnv, id: \.self) { env in
                                Text("• \(env)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    if !skill.missingOs.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Requires platform:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            ForEach(skill.missingOs, id: \.self) { os in
                                Text("• \(os)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // API Key management
            if let primaryEnvKey = skill.primaryEnvKey {
                apiKeySection(envKey: primaryEnvKey)
            }

            // Action buttons
            actionButtons
        }
        .padding(.leading, 24)
        .padding(.trailing, 4)
        .padding(.bottom, 4)
    }

    private var detailGrid: some View {
        Grid(alignment: .leading, verticalSpacing: 4) {
            if let location = skill.location {
                GridRow {
                    Text("Location")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 65, alignment: .leading)
                    Text(location)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(2)
                }
            }
            
            GridRow {
                Text("Status")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 65, alignment: .leading)
                Text(skill.gatingStatus ?? "unknown")
                    .font(.system(size: 11))
            }
            
            GridRow {
                Text("Loaded")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 65, alignment: .leading)
                Text(skill.loaded ? "Yes" : "No")
                    .font(.system(size: 11))
                    .foregroundStyle(skill.loaded ? .green : .secondary)
            }
        }
    }

    private func apiKeySection(envKey: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API Key (\(envKey))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            
            if skill.apiKeyConfigured && !editingApiKey {
                HStack {
                    Label("Configured", systemImage: "checkmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    
                    Spacer()
                    
                    Button("Update") {
                        onEditApiKey()
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            } else if editingApiKey {
                VStack(spacing: 6) {
                    SecureField("Enter API key", text: $apiKeyText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .onSubmit(onSaveApiKey)
                    
                    HStack {
                        Button("Save") {
                            onSaveApiKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        
                        Button("Cancel") {
                            onCancelApiKey()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Spacer()
                    }
                }
            } else {
                HStack {
                    Label("Not configured", systemImage: "exclamationmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    
                    Spacer()
                    
                    Button("Set API Key") {
                        onEditApiKey()
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary.opacity(0.3))
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if skill.canToggle {
                if skill.enabled {
                    Button {
                        onToggleEnabled()
                    } label: {
                        Label("Disable", systemImage: "pause")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isBusy)
                } else {
                    Button {
                        onToggleEnabled()
                    } label: {
                        Label("Enable", systemImage: "play")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isBusy)
                }
            } else if skill.blockedByAllowlist {
                Label("Blocked by allowlist", systemImage: "lock")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else if skill.hasMissingDeps {
                Label("Install dependencies to enable", systemImage: "arrow.down.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.top, 4)
    }
}
