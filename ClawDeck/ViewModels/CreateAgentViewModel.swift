import Foundation
import SwiftUI

/// View model for creating a new agent on a gateway via config.patch.
@Observable
@MainActor
final class CreateAgentViewModel {
    // MARK: - Form fields

    /// Agent ID (slug). Must be lowercase, alphanumeric + hyphens.
    var agentId: String = ""

    /// Display name for the agent.
    var displayName: String = ""

    /// Emoji for the agent avatar.
    var emoji: String = ""

    /// Workspace path (default: ~/clawd-<agentId>).
    var workspace: String = ""

    /// Selected model qualified ID (provider/model).
    var selectedModel: String = ""

    /// Target gateway profile ID for creating the agent.
    var targetGatewayId: String = ""

    // MARK: - State

    /// Whether the form is currently saving.
    var isSaving = false

    /// Gateway restart/reconnect progress after config patch.
    var restartPhase: RestartPhase = .none

    /// Error message to display.
    var errorMessage: String?

    /// Whether creation completed successfully.
    var isComplete = false

    enum RestartPhase: Equatable {
        case none
        case applyingConfig
        case waitingForRestart
        case reconnecting
        case done
    }

    // MARK: - Validation

    /// Whether the agent ID is valid (lowercase slug).
    var isAgentIdValid: Bool {
        let trimmed = agentId.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let slugRegex = /^[a-z][a-z0-9-]*$/
        return trimmed.wholeMatch(of: slugRegex) != nil
    }

    /// Validation message for the agent ID field.
    var agentIdValidationMessage: String? {
        let trimmed = agentId.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if trimmed.first?.isUppercase == true || trimmed.contains(" ") {
            return "Must be lowercase with no spaces (e.g. \"work-agent\")"
        }
        if !isAgentIdValid {
            return "Must start with a letter, only lowercase letters, numbers, and hyphens"
        }
        if existingAgentIds.contains(trimmed) {
            return "An agent with this ID already exists on the gateway"
        }
        return nil
    }

    /// Whether the agent ID conflicts with an existing agent on the target gateway.
    var isAgentIdConflicting: Bool {
        existingAgentIds.contains(agentId.trimmingCharacters(in: .whitespaces))
    }

    /// Whether the form can be submitted.
    var canSubmit: Bool {
        isAgentIdValid && !isAgentIdConflicting && !isSaving && !targetGatewayId.isEmpty
    }

    /// Computed default workspace path based on agent ID.
    var defaultWorkspace: String {
        let id = agentId.trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? "~/clawd-agent" : "~/clawd-\(id)"
    }

    /// The effective workspace (user override or computed default).
    var effectiveWorkspace: String {
        workspace.trimmingCharacters(in: .whitespaces).isEmpty ? defaultWorkspace : workspace
    }

    // MARK: - Private

    /// Existing agent IDs on the target gateway (for conflict detection).
    private var existingAgentIds: Set<String> = []

    /// Config hash for optimistic concurrency.
    private var configHash: String = ""

    /// Reference to the app view model.
    private weak var appViewModel: AppViewModel?

    // MARK: - Init

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel

        // Default target gateway to the active one
        if let binding = appViewModel.activeBinding {
            targetGatewayId = binding.gatewayId
        } else if let first = appViewModel.gatewayManager.gatewayProfiles.first {
            targetGatewayId = first.id
        }

        loadExistingAgents()
    }

    // MARK: - Loading

    /// Load existing agent IDs from the target gateway for conflict detection.
    func loadExistingAgents() {
        guard let appViewModel else { return }
        if let agents = appViewModel.gatewayManager.agentSummaries[targetGatewayId] {
            existingAgentIds = Set(agents.map { $0.id })
        }
    }

    /// Fetch the current config hash (needed for config.patch).
    func fetchConfigHash() async {
        guard let client = appViewModel?.gatewayManager.client(for: targetGatewayId) else { return }
        do {
            let result = try await client.configGet()
            configHash = result.hash ?? ""
        } catch {
            AppLogger.error("Failed to fetch config hash: \(error)", category: "Session")
        }
    }

    // MARK: - Creation

    /// Create the agent by sending a config.patch to the gateway.
    /// Returns `true` on success.
    @discardableResult
    func createAgent() async -> Bool {
        guard canSubmit else { return false }
        guard let appViewModel else {
            errorMessage = "No app context available"
            return false
        }

        guard let client = appViewModel.gatewayManager.client(for: targetGatewayId) else {
            errorMessage = "Not connected to the target gateway"
            return false
        }

        isSaving = true
        errorMessage = nil

        do {
            // Ensure we have a fresh config hash
            if configHash.isEmpty {
                await fetchConfigHash()
            }

            // Build the config.patch payload
            let patch = buildConfigPatch()
            let patchData = try JSONSerialization.data(
                withJSONObject: patch,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            guard let patchString = String(data: patchData, encoding: .utf8) else {
                throw CreateAgentError.jsonSerializationFailed
            }

            // Phase 1: Applying config
            restartPhase = .applyingConfig
            try await client.configPatch(
                raw: patchString,
                baseHash: configHash,
                note: "New agent '\(agentId)' created via ClawDeck"
            )

            // Phase 2: Waiting for gateway restart
            restartPhase = .waitingForRestart
            AppLogger.info("Config patch applied for new agent '\(agentId)', waiting for restart...", category: "Session")
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            // Phase 3: Reconnecting
            restartPhase = .reconnecting
            if !appViewModel.gatewayManager.isConnected(targetGatewayId) {
                AppLogger.debug("Reconnecting after creating agent...", category: "Session")
                await appViewModel.gatewayManager.reconnect(gatewayId: targetGatewayId)
                await appViewModel.loadInitialData()
            }

            // Phase 4: Create agent binding and add to rail
            let binding = AgentBinding(
                gatewayId: targetGatewayId,
                agentId: agentId.trimmingCharacters(in: .whitespaces),
                localDisplayName: displayName.isEmpty ? nil : displayName,
                railOrder: appViewModel.gatewayManager.sortedAgentBindings.count + 1
            )
            appViewModel.gatewayManager.addAgentBinding(binding)

            restartPhase = .done
            isComplete = true
            isSaving = false

            AppLogger.info("Agent '\(agentId)' created successfully", category: "Session")

            // Switch to the new agent
            await appViewModel.switchAgent(binding)

            return true
        } catch {
            errorMessage = "Failed to create agent: \(error.localizedDescription)"
            restartPhase = .none
            isSaving = false
            return false
        }
    }

    // MARK: - Private helpers

    /// Build the config.patch JSON payload for adding a new agent.
    private func buildConfigPatch() -> [String: Any] {
        let trimmedId = agentId.trimmingCharacters(in: .whitespaces)

        var agentEntry: [String: Any] = ["id": trimmedId]

        // Workspace
        agentEntry["workspace"] = effectiveWorkspace

        // Identity
        var identity: [String: Any] = [:]
        let name = displayName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            identity["name"] = name
        }
        let emojiTrimmed = emoji.trimmingCharacters(in: .whitespaces)
        if !emojiTrimmed.isEmpty {
            identity["emoji"] = emojiTrimmed
        }
        if !identity.isEmpty {
            agentEntry["identity"] = identity
        }

        var patch: [String: Any] = [:]
        var agentsPatch: [String: Any] = [:]
        agentsPatch["list"] = [agentEntry]

        // Model (only if explicitly selected)
        let model = selectedModel.trimmingCharacters(in: .whitespaces)
        if !model.isEmpty {
            agentsPatch["defaults"] = [
                "model": ["primary": model]
            ]
        }

        patch["agents"] = agentsPatch
        return patch
    }
}

// MARK: - Errors

enum CreateAgentError: Error, LocalizedError {
    case jsonSerializationFailed
    case noActiveConnection

    var errorDescription: String? {
        switch self {
        case .jsonSerializationFailed:
            return "Failed to serialize configuration JSON"
        case .noActiveConnection:
            return "No active gateway connection"
        }
    }
}
