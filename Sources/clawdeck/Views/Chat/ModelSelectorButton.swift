import SwiftUI

/// Compact pill button showing the active model name, with a popover for switching models.
///
/// Placed above the composer, right-aligned.
/// When the session has a per-session model override, a small dot indicator
/// distinguishes it from the agent's default.
struct ModelSelectorButton: View {
    /// The session's per-session model override (nil = using default).
    let currentModel: String?

    /// The agent-level default model ID (from SessionsListResult.defaults).
    let defaultModel: String?

    /// All available models from the gateway.
    let models: [GatewayModel]

    /// Called when the user selects a model. Pass `nil` to reset to default.
    let onSelect: (String?) -> Void

    @State private var isPopoverPresented = false

    /// The effective model ID to display (override or default).
    private var effectiveModelId: String? {
        currentModel ?? defaultModel
    }

    /// Whether the session has a per-session override.
    private var hasOverride: Bool {
        currentModel != nil
    }

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                if hasOverride {
                    Circle()
                        .fill(.blue)
                        .frame(width: 5, height: 5)
                }
                Text(pillDisplayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
            .overlay(
                Capsule()
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Change model")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
            // Snapshot models at popover open time so parent re-renders
            // (e.g. from session.model mutation) don't rebuild the popover
            // while it's animating closed — which causes a hang with 600+ models.
            ModelSelectorPopover(
                currentModel: currentModel,
                defaultModel: defaultModel,
                models: models,
                onSelect: { modelId in
                    isPopoverPresented = false
                    // Defer the callback so the popover dismissal animation
                    // completes before we mutate observable state.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onSelect(modelId)
                    }
                }
            )
        }
    }

    /// Short name for the pill (e.g., "Sonnet 4", "GPT-4o").
    private var pillDisplayName: String {
        guard let modelId = effectiveModelId else { return "Model" }
        return ModelDisplayHelper.pillName(for: modelId, models: models)
    }
}

// MARK: - Popover Content

/// Popover listing all available models grouped by provider, with a "Default" option at top.
private struct ModelSelectorPopover: View {
    let currentModel: String?
    let defaultModel: String?
    let models: [GatewayModel]
    let onSelect: (String?) -> Void

    @State private var searchText = ""

    /// Models filtered by search, then grouped by provider.
    private var groupedModels: [(provider: String, models: [GatewayModel])] {
        let filtered: [GatewayModel]
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            filtered = models
        } else {
            filtered = models.filter {
                $0.id.localizedCaseInsensitiveContains(query) ||
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.provider.localizedCaseInsensitiveContains(query)
            }
        }

        let grouped = Dictionary(grouping: filtered, by: { $0.provider })
        return grouped
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { (provider: $0.key, models: $0.value) }
    }

    /// The effective model ID that's currently active (for checkmark display).
    private var activeModelId: String? {
        currentModel ?? defaultModel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search models…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Default option (always visible)
                    if searchText.isEmpty {
                        defaultRow
                        Divider()
                            .padding(.vertical, 4)
                    }

                    // Grouped models
                    ForEach(groupedModels, id: \.provider) { group in
                        providerSection(group.provider, models: group.models)
                    }

                    if groupedModels.isEmpty && !searchText.isEmpty {
                        Text("No models match \"\(searchText)\"")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 340, height: 400)
    }

    // MARK: - Default Row

    private var defaultRow: some View {
        Button {
            onSelect(nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: currentModel == nil ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(currentModel == nil ? .blue : .secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Default")
                        .font(.system(size: 12, weight: .medium))
                    if let defaultModel {
                        Text(ModelDisplayHelper.displayName(for: defaultModel, models: models))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(currentModel == nil ? Color.accentColor.opacity(0.08) : .clear)
        )
    }

    // MARK: - Provider Section

    private func providerSection(_ provider: String, models: [GatewayModel]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ModelDisplayHelper.prettifyProvider(provider))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.horizontal, 6)
                .padding(.top, 6)
                .padding(.bottom, 2)

            ForEach(models) { model in
                modelRow(model)
            }
        }
    }

    // MARK: - Model Row

    /// Qualified model ID for the gateway: "provider/id".
    private func qualifiedId(_ model: GatewayModel) -> String {
        "\(model.provider)/\(model.id)"
    }

    private func modelRow(_ model: GatewayModel) -> some View {
        let isSelected = activeModelId == qualifiedId(model)

        return Button {
            onSelect(qualifiedId(model))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name.isEmpty ? model.id : model.name)
                        .font(.system(size: 12, weight: .regular))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(model.id)
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Badges
                HStack(spacing: 4) {
                    if model.reasoning == true {
                        BadgePill(text: "reasoning", color: .purple)
                    }
                    if let ctx = model.contextWindow, ctx > 0 {
                        BadgePill(text: formatContextWindow(ctx), color: .gray)
                    }
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : .clear)
        )
    }

    /// Format a context window size (e.g., 200000 → "200k").
    private func formatContextWindow(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let m = Double(tokens) / 1_000_000.0
            return m.truncatingRemainder(dividingBy: 1.0) == 0
                ? "\(Int(m))M"
                : String(format: "%.1fM", m)
        } else if tokens >= 1000 {
            let k = Double(tokens) / 1000.0
            return k.truncatingRemainder(dividingBy: 1.0) == 0
                ? "\(Int(k))k"
                : String(format: "%.0fk", k)
        }
        return "\(tokens)"
    }
}

// MARK: - Badge Pill

/// Tiny inline badge for metadata (e.g., "200k", "reasoning").
private struct BadgePill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color.opacity(0.8))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill(color.opacity(0.1))
            )
    }
}

// MARK: - Model Display Helper

/// Utility for abbreviating model IDs into human-friendly display names.
enum ModelDisplayHelper {
    /// Find a model by qualified ID ("provider/id") or bare ID.
    private static func findModel(_ modelId: String, in models: [GatewayModel]) -> GatewayModel? {
        // Try qualified match first: "provider/id"
        let parts = modelId.split(separator: "/", maxSplits: 1)
        if parts.count == 2 {
            let provider = String(parts[0])
            let bareId = String(parts[1])
            if let match = models.first(where: { $0.provider == provider && $0.id == bareId }) {
                return match
            }
        }
        // Fall back to bare ID match
        return models.first(where: { $0.id == modelId })
    }

    /// Full display name for the popover (e.g., "Claude Sonnet 4").
    static func displayName(for modelId: String, models: [GatewayModel]) -> String {
        if let model = findModel(modelId, in: models), !model.name.isEmpty {
            return model.name
        }
        // Strip provider prefix for display
        let parts = modelId.split(separator: "/", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : modelId
    }

    /// Short name for the compact pill button (e.g., "Sonnet 4", "GPT-4o").
    static func pillName(for modelId: String, models: [GatewayModel]) -> String {
        // First try finding the model and abbreviate its name
        if let model = findModel(modelId, in: models), !model.name.isEmpty {
            return abbreviate(model.name)
        }

        // Strip provider prefix, then abbreviate
        let parts = modelId.split(separator: "/", maxSplits: 1)
        let raw = parts.count > 1 ? String(parts[1]) : modelId
        return abbreviate(raw)
    }

    /// Capitalize and prettify a provider name (e.g., "anthropic" → "Anthropic").
    static func prettifyProvider(_ provider: String) -> String {
        let known: [String: String] = [
            "anthropic": "Anthropic",
            "openai": "OpenAI",
            "google": "Google",
            "meta": "Meta",
            "mistral": "Mistral",
            "cohere": "Cohere",
            "deepseek": "DeepSeek",
            "xai": "xAI",
            "groq": "Groq",
            "amazon": "Amazon",
            "perplexity": "Perplexity",
        ]
        return known[provider.lowercased()] ?? provider.capitalized
    }

    /// Abbreviate a model name or raw ID for the compact pill.
    ///
    /// Examples:
    /// - "Claude Sonnet 4" → "Sonnet 4"
    /// - "Claude Opus 4" → "Opus 4"
    /// - "claude-sonnet-4-20250514" → "Sonnet 4"
    /// - "gpt-4o-2024-08-06" → "GPT-4o"
    /// - "gemini-2.5-pro" → "Gemini 2.5 Pro"
    private static func abbreviate(_ name: String) -> String {
        // Known patterns — check display names first
        let patterns: [(match: String, result: String)] = [
            // Anthropic display names
            ("Claude Sonnet 4", "Sonnet 4"),
            ("Claude Opus 4", "Opus 4"),
            ("Claude Haiku 3.5", "Haiku 3.5"),
            ("Claude Sonnet 3.5", "Sonnet 3.5"),

            // Anthropic raw IDs
            ("claude-sonnet-4", "Sonnet 4"),
            ("claude-opus-4", "Opus 4"),
            ("claude-haiku-3", "Haiku 3.5"),
            ("claude-sonnet-3", "Sonnet 3.5"),

            // OpenAI
            ("gpt-4.1", "GPT-4.1"),
            ("gpt-4o", "GPT-4o"),
            ("gpt-4-turbo", "GPT-4 Turbo"),
            ("gpt-4", "GPT-4"),
            ("o3-pro", "o3 Pro"),
            ("o3-mini", "o3 Mini"),
            ("o3", "o3"),
            ("o4-mini", "o4 Mini"),

            // Google
            ("gemini-2.5-pro", "Gemini 2.5 Pro"),
            ("gemini-2.5-flash", "Gemini 2.5 Flash"),
            ("gemini-2.0-flash", "Gemini 2.0 Flash"),
            ("gemini-1.5-pro", "Gemini 1.5 Pro"),

            // DeepSeek
            ("deepseek-r1", "DeepSeek R1"),
            ("deepseek-v3", "DeepSeek V3"),
        ]

        let lowered = name.lowercased()
        for pattern in patterns {
            if lowered.contains(pattern.match.lowercased()) {
                return pattern.result
            }
        }

        // Fallback: strip date suffixes like "-20250514" and truncate
        let cleaned = name
            .replacingOccurrences(
                of: #"-\d{8,}$"#,
                with: "",
                options: .regularExpression
            )

        // Capitalize if it looks like a raw ID with dashes
        if cleaned.contains("-") && !cleaned.contains(" ") {
            return cleaned
                .split(separator: "-")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }

        return cleaned
    }
}
