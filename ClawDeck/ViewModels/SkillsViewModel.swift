import SwiftUI

/// An install option for a skill dependency.
struct SkillInstallOption: Identifiable {
    let id: String
    let kind: String       // "brew", "node", "go", "uv", "download"
    let label: String
    let bins: [String]
    
    var displayLabel: String { label.isEmpty ? "Install (\(kind))" : label }
}

/// Represents a skill for the UI.
struct SkillInfo: Identifiable {
    let key: String
    let name: String
    let description: String?
    var enabled: Bool
    let eligible: Bool
    let loaded: Bool
    let source: String?
    let location: String?
    let gatingStatus: String?
    let missingBins: [String]
    let missingAnyBins: [String]
    let missingEnv: [String]
    let missingOs: [String]
    let apiKeyConfigured: Bool
    let primaryEnvKey: String?
    let blockedByAllowlist: Bool
    let installOptions: [SkillInstallOption]
    
    var id: String { key }
    
    var isReady: Bool { eligible && enabled }
    var isDisabledByUser: Bool { !enabled && eligible }
    var isUnavailable: Bool { !eligible && enabled }
    var needsApiKey: Bool { primaryEnvKey != nil && !apiKeyConfigured }
    var hasMissingDeps: Bool { !missingBins.isEmpty || !missingAnyBins.isEmpty || !missingEnv.isEmpty || !missingOs.isEmpty }
    var canInstall: Bool { !installOptions.isEmpty && hasMissingDeps && !blockedByAllowlist && missingOs.isEmpty }
    
    /// Whether the user can meaningfully toggle this skill
    var canToggle: Bool { eligible || isDisabledByUser }
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
    
    // Install state
    var installingSkillKeys: Set<String> = []
    var installResults: [String: (ok: Bool, message: String)] = [:]
    
    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
    }
    
    var groupedSkills: (ready: [SkillInfo], disabled: [SkillInfo], unavailable: [SkillInfo]) {
        let ready = skills.filter { $0.isReady }
        let disabled = skills.filter { $0.isDisabledByUser }
        let unavailable = skills.filter { $0.isUnavailable }
        return (ready, disabled, unavailable)
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
        guard skill.canToggle else { return }
        guard let appViewModel = appViewModel,
              let client = appViewModel.activeClient else { return }
        busySkillKeys.insert(skill.key)
        defer { busySkillKeys.remove(skill.key) }
        
        do {
            try await client.skillsUpdate(skillKey: skill.key, enabled: !skill.enabled)
            // Refresh from gateway to get accurate state
            await loadSkills()
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
    
    func installSkill(_ skill: SkillInfo, option: SkillInstallOption? = nil) async {
        guard let appViewModel = appViewModel,
              let client = appViewModel.activeClient else { return }
        
        installingSkillKeys.insert(skill.key)
        installResults.removeValue(forKey: skill.key)
        defer { installingSkillKeys.remove(skill.key) }
        
        do {
            let _ = try await client.skillsInstall(name: skill.name)
            installResults[skill.key] = (ok: true, message: "Installed successfully")
            // Refresh to show updated status
            await loadSkills()
        } catch {
            installResults[skill.key] = (ok: false, message: error.localizedDescription)
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
            
            // Gateway sends "eligible" — skill has all deps and is not blocked
            let eligible = raw["eligible"] as? Bool ?? false
            let loaded = raw["loaded"] as? Bool ?? eligible
            let blockedByAllowlist = raw["blockedByAllowlist"] as? Bool ?? false
            
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
            let missingAnyBins = missing["anyBins"] as? [String] ?? []
            let missingEnv = missing["env"] as? [String] ?? gating["missingEnv"] as? [String] ?? []
            let missingOs = missing["os"] as? [String] ?? []
            
            // Check if apiKey is configured via primaryEnv
            let primaryEnvKey = raw["primaryEnv"] as? String ?? gating["primaryEnvKey"] as? String
            let apiKeyConfigured = gating["apiKeyConfigured"] as? Bool ?? (primaryEnvKey != nil && !missingEnv.contains(primaryEnvKey!))
            
            // Parse install options
            let rawInstall = raw["install"] as? [[String: Any]] ?? []
            let installOptions: [SkillInstallOption] = rawInstall.compactMap { spec in
                let specId = spec["id"] as? String ?? ""
                let kind = spec["kind"] as? String ?? ""
                let label = spec["label"] as? String ?? ""
                let bins = spec["bins"] as? [String] ?? []
                guard !kind.isEmpty else { return nil }
                return SkillInstallOption(id: specId, kind: kind, label: label, bins: bins)
            }
            
            parsed.append(SkillInfo(
                key: key, name: name, description: description,
                enabled: enabled, eligible: eligible, loaded: loaded, source: source,
                location: location, gatingStatus: gatingStatus,
                missingBins: missingBins, missingAnyBins: missingAnyBins,
                missingEnv: missingEnv, missingOs: missingOs,
                apiKeyConfigured: apiKeyConfigured, primaryEnvKey: primaryEnvKey,
                blockedByAllowlist: blockedByAllowlist, installOptions: installOptions
            ))
        }
        
        skills = parsed.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}