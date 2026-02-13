import Foundation
import SwiftUI

/// View model for editing gateway configuration.
@Observable
@MainActor
final class GatewaySettingsViewModel {
    // MARK: - State

    /// The raw JSON config text being edited.
    var configText: String = ""

    /// The original raw text from the gateway (for dirty detection).
    private var originalText: String = ""

    /// Config hash for optimistic concurrency (required by config.patch).
    private var configHash: String = ""

    /// Whether the config has unsaved changes.
    var isDirty: Bool {
        configText != originalText
    }

    /// Loading state.
    var isLoading = false

    /// Saving state.
    var isSaving = false

    /// Error message to display.
    var errorMessage: String?

    /// Success message to display briefly.
    var successMessage: String?

    /// Whether the config exists on disk.
    var configExists = false

    /// Config file path.
    var configPath: String?

    /// Validation issues from the gateway.
    var validationIssues: [String] = []

    /// Validation warnings from the gateway.
    var validationWarnings: [String] = []

    /// Reference to the connection manager for gateway access.
    private weak var connectionManager: ConnectionManager?

    // MARK: - Init

    init(connectionManager: ConnectionManager?) {
        self.connectionManager = connectionManager
    }

    // MARK: - Actions

    /// Fetch the current config from the gateway.
    func loadConfig() async {
        guard let client = connectionManager?.activeClient else {
            errorMessage = "Not connected to gateway"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await client.configGet()
            configExists = result.exists
            configPath = result.path
            configHash = result.hash ?? ""
            validationIssues = result.issues ?? []
            validationWarnings = result.warnings ?? []

            if let raw = result.raw {
                // Pretty-print the JSON for editing
                configText = prettifyJSON(raw)
                originalText = configText
            } else {
                configText = "{\n  \n}"
                originalText = configText
            }
        } catch {
            errorMessage = "Failed to load config: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Save the edited config back to the gateway via config.patch.
    func saveConfig() async {
        guard let client = connectionManager?.activeClient else {
            errorMessage = "Not connected to gateway"
            return
        }

        guard isDirty else { return }

        // Validate JSON locally first
        guard isValidJSON(configText) else {
            errorMessage = "Invalid JSON — please fix syntax errors before saving."
            return
        }

        isSaving = true
        errorMessage = nil
        successMessage = nil

        do {
            // Use config.patch with the full config as raw
            // The gateway will validate, write, and restart
            try await client.configPatch(
                raw: configText,
                baseHash: configHash,
                note: "Edited via ClawdDeck Settings"
            )

            successMessage = "Config saved. Gateway will restart."
            originalText = configText

            // Clear success after a delay
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    if self.successMessage == "Config saved. Gateway will restart." {
                        self.successMessage = nil
                    }
                }
            }
        } catch {
            errorMessage = "Failed to save config: \(error.localizedDescription)"
        }

        isSaving = false
    }

    /// Revert to the last saved state.
    func revert() {
        configText = originalText
        errorMessage = nil
    }

    /// Reload from gateway (discards local changes).
    func reload() async {
        await loadConfig()
    }

    // MARK: - Helpers

    /// Pretty-print JSON string.
    private func prettifyJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(
                  withJSONObject: jsonObject,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let prettyString = String(data: prettyData, encoding: .utf8)
        else {
            return raw
        }
        return prettyString
    }

    /// Check if a string is valid JSON.
    private func isValidJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}
