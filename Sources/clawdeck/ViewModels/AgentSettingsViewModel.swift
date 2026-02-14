import AppKit
import Foundation
import SwiftUI

/// View model for editing agent settings across gateway config and local bindings.
@Observable
@MainActor
final class AgentSettingsViewModel {
    // MARK: - State
    
    /// Loading state.
    var isLoading = false
    
    /// Saving state.
    var isSaving = false
    
    /// Error message to display.
    var errorMessage: String?
    
    /// Success message to display briefly.
    var successMessage: String?
    
    /// Config hash for optimistic concurrency (required by config.patch).
    private var configHash: String = ""
    
    /// Original config JSON for detecting changes.
    private var originalConfig: [String: Any] = [:]
    
    // MARK: - Agent Identity (from gateway config)
    
    /// Agent display name (from agents.list[].identity.name).
    var agentDisplayName: String = ""
    
    /// Agent emoji (from agents.list[].identity.emoji).
    var agentEmoji: String = ""
    
    /// Agent accent color (from agents.list[].identity.theme or ui.seamColor).
    var agentAccentColor: Color = .blue
    
    /// Primary model (from agents.defaults.model.primary).
    var primaryModel: String = ""

    /// Selected SF Symbol icon for the agent rail (from AgentBinding.localAvatarName).
    var selectedIcon: String?
    
    // MARK: - Gateway Connection (local settings)
    
    /// Gateway display name (local override).
    var gatewayDisplayName: String = ""
    
    /// Gateway host.
    var gatewayHost: String = ""
    
    /// Gateway port.
    var gatewayPort: String = ""
    
    /// Gateway TLS toggle.
    var gatewayUseTLS: Bool = true
    
    /// Gateway token (sensitive).
    var gatewayToken: String = ""
    
    // MARK: - Private properties
    
    /// Reference to the app view model.
    private weak var appViewModel: AppViewModel?
    
    /// Current agent binding.
    private var currentBinding: AgentBinding?
    
    /// Current gateway profile.
    private var currentProfile: GatewayProfile?
    
    // MARK: - Init
    
    init(appViewModel: AppViewModel?) {
        self.appViewModel = appViewModel
        loadInitialValues()
    }
    
    // MARK: - Loading
    
    /// Load current values from gateway config and local settings.
    func loadConfig() async {
        guard let appViewModel, 
              let client = appViewModel.activeClient,
              let binding = appViewModel.activeBinding else {
            errorMessage = "No active gateway connection"
            return
        }
        
        currentBinding = binding
        
        // Find the gateway profile
        if let profile = appViewModel.gatewayManager.gatewayProfiles.first(where: { $0.id == binding.gatewayId }) {
            currentProfile = profile
            loadGatewaySettings(from: profile)
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await client.configGet()
            configHash = result.hash ?? ""
            
            if let rawConfig = result.raw {
                await parseGatewayConfig(rawConfig)
            }
        } catch {
            errorMessage = "Failed to load config: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// Parse the gateway config JSON and extract relevant values.
    private func parseGatewayConfig(_ rawConfig: String) async {
        guard let data = rawConfig.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            errorMessage = "Failed to parse config JSON"
            return
        }
        
        originalConfig = json
        
        // Extract agent identity settings
        if let agents = json["agents"] as? [String: Any],
           let agentsList = agents["list"] as? [[String: Any]],
           let currentAgent = agentsList.first(where: { ($0["id"] as? String) == currentBinding?.agentId }),
           let identity = currentAgent["identity"] as? [String: Any] {
            
            agentDisplayName = identity["name"] as? String ?? ""
            agentEmoji = identity["emoji"] as? String ?? ""
            
            if let themeColor = identity["theme"] as? String {
                agentAccentColor = colorFromString(themeColor) ?? .blue
            }
        }
        
        // Extract UI seam color as fallback
        if agentAccentColor == .blue,
           let ui = json["ui"] as? [String: Any],
           let seamColor = ui["seamColor"] as? String {
            agentAccentColor = colorFromString(seamColor) ?? .blue
        }
        
        // Extract primary model
        if let agents = json["agents"] as? [String: Any],
           let defaults = agents["defaults"] as? [String: Any],
           let model = defaults["model"] as? [String: Any],
           let primary = model["primary"] as? String {
            primaryModel = primary
        }

        // Snapshot originals for dirty detection
        originalAgentName = agentDisplayName
        originalAgentEmoji = agentEmoji
        originalPrimaryModel = primaryModel
    }
    
    /// Load initial values from current binding and profile.
    private func loadInitialValues() {
        guard let appViewModel else { return }
        
        if let binding = appViewModel.activeBinding {
            currentBinding = binding

            // Load icon from binding's localAvatarName (stored as "sf:symbolname")
            if let avatarName = binding.localAvatarName, avatarName.hasPrefix("sf:") {
                selectedIcon = String(avatarName.dropFirst(3))
            }
            
            if let profile = appViewModel.gatewayManager.gatewayProfiles.first(where: { $0.id == binding.gatewayId }) {
                currentProfile = profile
                loadGatewaySettings(from: profile)
            }
        }
    }
    
    /// Load gateway connection settings from profile.
    private func loadGatewaySettings(from profile: GatewayProfile) {
        gatewayDisplayName = profile.displayName
        gatewayHost = profile.host
        gatewayPort = String(profile.port)
        gatewayUseTLS = profile.useTLS
        gatewayToken = profile.token ?? ""

        // Snapshot for dirty detection
        originalGatewayDisplayName = gatewayDisplayName
        originalGatewayHost = gatewayHost
        originalGatewayPort = gatewayPort
        originalGatewayUseTLS = gatewayUseTLS
        originalGatewayToken = gatewayToken
    }
    
    // MARK: - Saving
    
    /// Save all changes to both gateway config and local settings.
    /// Returns `true` on success so the caller can dismiss.
    @discardableResult
    func saveChanges() async -> Bool {
        guard let appViewModel else {
            errorMessage = "No app context available"
            return false
        }
        
        isSaving = true
        errorMessage = nil
        successMessage = nil
        
        do {
            // Save gateway config changes
            try await saveGatewayConfig()
            
            // Save local profile changes
            await saveGatewayProfile()
            
            successMessage = "Settings saved successfully"
            isSaving = false
            return true
        } catch {
            errorMessage = "Failed to save settings: \(error.localizedDescription)"
            isSaving = false
            return false
        }
    }
    
    /// Save gateway configuration changes.
    private func saveGatewayConfig() async throws {
        guard let client = appViewModel?.activeClient,
              let binding = currentBinding else {
            throw AgentSettingsError.noActiveConnection
        }

        // Build a minimal config patch (only changed fields)
        var patch: [String: Any] = [:]

        // Agent identity + model live under "agents"
        var agentEntry: [String: Any] = ["id": binding.agentId]
        var identity: [String: Any] = [:]

        if !agentDisplayName.isEmpty {
            identity["name"] = agentDisplayName
        }
        if !agentEmoji.isEmpty {
            identity["emoji"] = agentEmoji
        }
        let colorHex = stringFromColor(agentAccentColor)
        identity["theme"] = colorHex

        if !identity.isEmpty {
            agentEntry["identity"] = identity
        }

        var agentsPatch: [String: Any] = [:]
        agentsPatch["list"] = [agentEntry]

        // Primary model
        if !primaryModel.isEmpty {
            agentsPatch["defaults"] = [
                "model": ["primary": primaryModel]
            ]
        }

        patch["agents"] = agentsPatch

        // Also set ui.seamColor to keep webchat in sync
        patch["ui"] = ["seamColor": colorHex.replacingOccurrences(of: "#", with: "")]

        // Convert to JSON string
        let patchData = try JSONSerialization.data(withJSONObject: patch, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        guard let patchString = String(data: patchData, encoding: .utf8) else {
            throw AgentSettingsError.jsonSerializationFailed
        }

        // Send the patch (gateway merges it with existing config).
        // The gateway will restart after applying, dropping our WebSocket.
        try await client.configPatch(
            raw: patchString,
            baseHash: configHash,
            note: "Agent settings updated via ClawDeck"
        )

        // Give the gateway time to restart (restartDelayMs defaults to 2000ms,
        // plus startup time). Then trigger a fresh reconnect.
        print("[AgentSettings] Config patch applied, waiting for gateway restart...")
        try? await Task.sleep(nanoseconds: 4_000_000_000)

        // Force reconnect if not already reconnected
        if let appVM = appViewModel,
           let binding = appVM.activeBinding,
           !appVM.gatewayManager.isConnected(binding.gatewayId) {
            print("[AgentSettings] Reconnecting after config patch...")
            await appVM.gatewayManager.reconnect(gatewayId: binding.gatewayId)
            // Reload agents/sessions after reconnecting
            await appVM.loadInitialData()
        }
    }
    
    /// Save gateway profile changes to local storage.
    private func saveGatewayProfile() async {
        guard let appViewModel,
              var profile = currentProfile else { return }
        
        // Update profile with new values
        profile.displayName = gatewayDisplayName
        profile.host = gatewayHost
        
        // Validate port number
        if let port = Int(gatewayPort), port > 0 && port <= 65535 {
            profile.port = port
        }
        
        profile.useTLS = gatewayUseTLS
        profile.token = gatewayToken.isEmpty ? nil : gatewayToken
        
        // Update in gateway manager
        appViewModel.gatewayManager.updateGatewayProfile(profile)
        currentProfile = profile
        
        // Update current binding
        if var binding = currentBinding {
            // Display name override
            let gatewayDefaultName = binding.displayName(from: appViewModel.gatewayManager)
            if !agentDisplayName.isEmpty && agentDisplayName != gatewayDefaultName {
                binding.localDisplayName = agentDisplayName
            } else {
                binding.localDisplayName = nil
            }

            // Icon (stored as "sf:symbolname")
            if let icon = selectedIcon {
                binding.localAvatarName = "sf:\(icon)"
            } else {
                binding.localAvatarName = nil
            }
            
            // Update through the gateway manager
            appViewModel.gatewayManager.updateAgentBinding(binding)
            currentBinding = binding
        }
    }
    
    // MARK: - Color Utilities
    
    /// Convert a color string (hex or color name) to SwiftUI Color.
    private func colorFromString(_ colorString: String) -> Color? {
        let trimmed = colorString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle common color names
        switch trimmed.lowercased() {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "orange": return .orange
        case "yellow": return .yellow
        case "purple": return .purple
        case "pink": return .pink
        case "gray", "grey": return .gray
        case "black": return .black
        case "white": return .white
        default: break
        }
        
        // Handle hex colors
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        
        guard hex.count == 6 || hex.count == 3 else { return nil }
        
        let hexString: String
        if hex.count == 3 {
            // Expand 3-digit hex (e.g., "f0a" -> "ff00aa")
            hexString = hex.compactMap { "\($0)\($0)" }.joined()
        } else {
            hexString = hex
        }
        
        guard let r = Int(hexString.prefix(2), radix: 16),
              let g = Int(hexString.dropFirst(2).prefix(2), radix: 16),
              let b = Int(hexString.suffix(2), radix: 16) else {
            return nil
        }
        
        return Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
    }
    
    /// Convert a SwiftUI Color to hex string.
    private func stringFromColor(_ color: Color) -> String {
        // Convert via NSColor for reliable component extraction on macOS
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
    
    // Original values for dirty detection
    private var originalAgentName = ""
    private var originalAgentEmoji = ""
    private var originalPrimaryModel = ""
    private var originalGatewayDisplayName = ""
    private var originalGatewayHost = ""
    private var originalGatewayPort = ""
    private var originalGatewayUseTLS = true
    private var originalGatewayToken = ""

    /// Check if settings have unsaved changes.
    var hasUnsavedChanges: Bool {
        agentDisplayName != originalAgentName ||
        agentEmoji != originalAgentEmoji ||
        primaryModel != originalPrimaryModel ||
        gatewayDisplayName != originalGatewayDisplayName ||
        gatewayHost != originalGatewayHost ||
        gatewayPort != originalGatewayPort ||
        gatewayUseTLS != originalGatewayUseTLS ||
        gatewayToken != originalGatewayToken
    }
}

// MARK: - Errors

enum AgentSettingsError: Error, LocalizedError {
    case noActiveConnection
    case jsonSerializationFailed
    
    var errorDescription: String? {
        switch self {
        case .noActiveConnection:
            return "No active gateway connection"
        case .jsonSerializationFailed:
            return "Failed to serialize configuration JSON"
        }
    }
}