import SwiftUI

/// Represents a skill for the UI.
struct SkillInfo: Identifiable {
    let key: String
    let name: String
    let description: String?
    var enabled: Bool
    let loaded: Bool
    let source: String?
    let location: String?
    let gatingStatus: String?
    let missingBins: [String]
    let missingEnv: [String]
    let apiKeyConfigured: Bool
    let primaryEnvKey: String?
    
    var id: String { key }
    
    var isReady: Bool { gatingStatus == "ready" }
    var needsApiKey: Bool { primaryEnvKey != nil && !apiKeyConfigured }
    var hasMissingDeps: Bool { !missingBins.isEmpty || !missingEnv.isEmpty }
}

@Observable
@MainActor
final class SkillsViewModel {
    private weak var appViewModel: AppViewModel?
    
    var skills: [SkillInfo] = []
    var isLoading = false
    var errorMessage: String?
    var expandedSkillKey: String?
    var busySkillKeys: Set<String> = []
    
    // API key editing
    var editingApiKeyFor: String?
    var apiKeyText: String = ""
    
    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
    }
    
    var groupedSkills: (enabled: [SkillInfo], disabled: [SkillInfo]) {
        let enabled = skills.filter { $0.enabled }
        let disabled = skills.filter { !$0.enabled }
        return (enabled, disabled)
    }
    
    func loadSkills() async {
        guard let appViewModel = appViewModel,
              let client = appViewModel.activeClient else {
            errorMessage = "Not connected to gateway"
            return
        }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let payload = try await client.skillsStatus()
            parseSkillsStatus(payload)
        } catch {
            errorMessage = "Failed to load skills: \(error.localizedDescription)"
        }
    }
    
    func toggleExpanded(_ key: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedSkillKey = (expandedSkillKey == key) ? nil : key
        }
    }
    
    func toggleEnabled(_ skill: SkillInfo) async {
        guard let appViewModel = appViewModel,
              let client = appViewModel.activeClient else { return }
        busySkillKeys.insert(skill.key)
        defer { busySkillKeys.remove(skill.key) }
        
        do {
            try await client.skillsUpdate(skillKey: skill.key, enabled: !skill.enabled)
            // Update local state
            if let index = skills.firstIndex(where: { $0.key == skill.key }) {
                skills[index] = SkillInfo(
                    key: skill.key, name: skill.name, description: skill.description,
                    enabled: !skill.enabled, loaded: skill.loaded, source: skill.source,
                    location: skill.location, gatingStatus: skill.gatingStatus,
                    missingBins: skill.missingBins, missingEnv: skill.missingEnv,
                    apiKeyConfigured: skill.apiKeyConfigured, primaryEnvKey: skill.primaryEnvKey
                )
            }
        } catch {
            errorMessage = "Failed to update skill: \(error.localizedDescription)"
        }
    }
    
    func saveApiKey(for skillKey: String) async {
        guard let appViewModel = appViewModel,
              let client = appViewModel.activeClient else { return }
        let trimmed = apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        busySkillKeys.insert(skillKey)
        defer { busySkillKeys.remove(skillKey) }
        
        do {
            try await client.skillsUpdate(skillKey: skillKey, apiKey: trimmed)
            editingApiKeyFor = nil
            apiKeyText = ""
            await loadSkills() // Refresh to show updated status
        } catch {
            errorMessage = "Failed to save API key: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Parsing
    
    private func parseSkillsStatus(_ payload: AnyCodable) {
        guard let dict = payload.dictValue else { return }
        let rawSkills = dict["skills"] as? [[String: Any]] ?? []
        
        var parsed: [SkillInfo] = []
        var seenKeys: Set<String> = []

        for raw in rawSkills {
            // Gateway sends "skillKey", not "key"
            let key = raw["skillKey"] as? String ?? raw["key"] as? String ?? ""
            guard !key.isEmpty, !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            let name = raw["name"] as? String ?? key
            let description = raw["description"] as? String
            
            // Gateway sends "disabled" (inverted), not "enabled"
            let disabled = raw["disabled"] as? Bool ?? false
            let enabled = raw["enabled"] as? Bool ?? !disabled
            
            // Gateway sends "eligible" instead of "loaded"
            let eligible = raw["eligible"] as? Bool ?? false
            let loaded = raw["loaded"] as? Bool ?? eligible
            
            let source = raw["source"] as? String
            let location = raw["filePath"] as? String ?? raw["location"] as? String
            
            // Gateway nests missing deps under "missing", not "gating"
            let missing = raw["missing"] as? [String: Any] ?? [:]
            let gating = raw["gating"] as? [String: Any] ?? [:]
            
            // Derive gating status from eligible/disabled
            let gatingStatus: String? = gating["status"] as? String ?? {
                if disabled { return "disabled" }
                if raw["blockedByAllowlist"] as? Bool == true { return "blocked" }
                if eligible { return "ready" }
                return "missing"
            }()
            
            let missingBins = missing["bins"] as? [String] ?? gating["missingBins"] as? [String] ?? []
            let missingEnv = missing["env"] as? [String] ?? gating["missingEnv"] as? [String] ?? []
            
            // Check if apiKey is configured via primaryEnv
            let primaryEnvKey = raw["primaryEnv"] as? String ?? gating["primaryEnvKey"] as? String
            let apiKeyConfigured = gating["apiKeyConfigured"] as? Bool ?? (primaryEnvKey != nil && !missingEnv.contains(primaryEnvKey!))
            
            parsed.append(SkillInfo(
                key: key, name: name, description: description,
                enabled: enabled, loaded: loaded, source: source,
                location: location, gatingStatus: gatingStatus,
                missingBins: missingBins, missingEnv: missingEnv,
                apiKeyConfigured: apiKeyConfigured, primaryEnvKey: primaryEnvKey
            ))
        }
        
        skills = parsed.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}