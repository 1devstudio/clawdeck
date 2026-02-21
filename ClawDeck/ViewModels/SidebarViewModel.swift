import Foundation
import SwiftUI

/// ViewModel for the sidebar containing agents and sessions.
@Observable
@MainActor
final class SidebarViewModel {
    // MARK: - Dependencies

    private let appViewModel: AppViewModel

    // MARK: - State

    /// Search/filter text for sessions.
    var searchText = ""

    /// Whether the session list is loading.
    var isLoading: Bool { appViewModel.isLoadingSessions }

    /// Whether sessions have been loaded at least once.
    var hasLoadedSessions: Bool { appViewModel.hasLoadedSessions }

    /// Currently hovered session (for context menu).
    var hoveredSessionKey: String?

    /// Session being renamed.
    var renamingSessionKey: String?
    var renameText = ""

    /// Display name of the active agent.
    var agentDisplayName: String {
        guard let binding = appViewModel.activeBinding else { return "clawdeck" }
        return binding.displayName(from: appViewModel.gatewayManager)
    }

    /// Agents from the app state.
    var agents: [Agent] {
        appViewModel.agents
    }

    /// Sessions from the app state, filtered by search.
    var filteredSessions: [Session] {
        let all = appViewModel.sessions
        if searchText.isEmpty { return all }
        return all.filter { session in
            session.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            (session.lastMessage?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    /// Sessions grouped by creation time (stable order that doesn't shift on activity).
    /// Memoized — recomputes only when the session list or search text changes.
    var groupedSessions: [(title: String, sessions: [Session])] {
        let version = groupingVersion
        if version == _lastGroupingVersion, let cached = _cachedGroupedSessions {
            return cached
        }
        let result = computeGroupedSessions()
        _cachedGroupedSessions = result
        _lastGroupingVersion = version
        return result
    }

    @ObservationIgnored private var _cachedGroupedSessions: [(title: String, sessions: [Session])]?
    @ObservationIgnored private var _lastGroupingVersion: Int = -1

    /// Starred sessions store (from app view model).
    private var starredStore: StarredSessionsStore {
        appViewModel.starredSessionsStore
    }

    /// Whether a session is starred.
    func isStarred(_ sessionKey: String) -> Bool {
        starredStore.isStarred(sessionKey)
    }

    /// Whether a session is currently loading its message history.
    func isLoadingHistory(_ sessionKey: String) -> Bool {
        appViewModel.historyLoadingKey == sessionKey
    }

    /// Toggle the starred state of a session.
    func toggleStar(_ sessionKey: String) {
        starredStore.toggle(sessionKey)
        // Invalidate the grouping cache
        _lastGroupingVersion = -1
    }

    /// Whether a session counts as "active" — streaming or had activity within
    /// the last 2 hours (based on `lastMessageAt` or `updatedAt`).
    private func isActive(_ session: Session) -> Bool {
        if appViewModel.messageStore.isStreaming(sessionKey: session.key) {
            return true
        }
        let recentThreshold: TimeInterval = 2 * 60 * 60  // 2 hours
        let lastActivity = session.lastMessageAt ?? session.updatedAt
        return lastActivity.timeIntervalSinceNow > -recentThreshold
    }

    /// A lightweight version key that changes when inputs to grouping change.
    private var groupingVersion: Int {
        var hasher = Hasher()
        hasher.combine(searchText)
        let sessions = appViewModel.sessions
        hasher.combine(sessions.count)
        for s in sessions {
            hasher.combine(s.key)
            hasher.combine(s.label)
        }
        // Include starred keys so starring/unstarring invalidates the cache
        let starredKeys = starredStore.starredKeys
        hasher.combine(starredKeys.count)
        for key in starredKeys.sorted() {
            hasher.combine(key)
        }
        return hasher.finalize()
    }

    /// Whether a group title is a History sub-group (Today, Yesterday, etc.).
    static let historySubgroups: Set<String> = ["Today", "Yesterday", "This Week", "Older"]

    private func computeGroupedSessions() -> [(title: String, sessions: [Session])] {
        let sorted = filteredSessions.sorted { ($0.createdAt) > ($1.createdAt) }
        let calendar = Calendar.current
        let now = Date()

        var starred: [Session] = []
        var active: [Session] = []
        var today: [Session] = []
        var yesterday: [Session] = []
        var thisWeek: [Session] = []
        var older: [Session] = []

        for session in sorted {
            if starredStore.isStarred(session.key) {
                starred.append(session)
            } else if isActive(session) {
                active.append(session)
            } else if calendar.isDateInToday(session.createdAt) {
                today.append(session)
            } else if calendar.isDateInYesterday(session.createdAt) {
                yesterday.append(session)
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
                      session.createdAt > weekAgo {
                thisWeek.append(session)
            } else {
                older.append(session)
            }
        }

        var groups: [(title: String, sessions: [Session])] = []
        if !starred.isEmpty   { groups.append(("Starred", starred)) }
        if !active.isEmpty    { groups.append(("Active", active)) }
        if !today.isEmpty     { groups.append(("Today", today)) }
        if !yesterday.isEmpty { groups.append(("Yesterday", yesterday)) }
        if !thisWeek.isEmpty  { groups.append(("This Week", thisWeek)) }
        if !older.isEmpty     { groups.append(("Older", older)) }
        return groups
    }

    /// Selected session key.
    var selectedSessionKey: String? {
        get { appViewModel.selectedSessionKey }
        set { appViewModel.selectedSessionKey = newValue }
    }

    // MARK: - Init

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
    }

    // MARK: - Actions

    /// Refresh sessions from the gateway.
    func refreshSessions() async {
        await appViewModel.refreshSessions()
    }

    /// Select a session.
    func selectSession(_ key: String) {
        appViewModel.selectSession(key)
    }

    /// Delete a session.
    func deleteSession(_ key: String) async {
        await appViewModel.deleteSession(key)
    }

    /// Begin renaming a session.
    func beginRename(_ key: String) {
        renamingSessionKey = key
        renameText = appViewModel.sessions.first { $0.key == key }?.displayTitle ?? ""
    }

    /// Commit the rename.
    func commitRename() async {
        guard let key = renamingSessionKey, !renameText.isEmpty else {
            renamingSessionKey = nil
            return
        }
        await appViewModel.renameSession(key, label: renameText)
        renamingSessionKey = nil
        renameText = ""
    }

    /// Cancel renaming.
    func cancelRename() {
        renamingSessionKey = nil
        renameText = ""
    }

    /// Create a new session.
    func createNewSession() async {
        await appViewModel.createNewSession()
    }

    /// Show the agent settings sheet for the active agent.
    func showAgentSettings() {
        appViewModel.editingAgentProfileId = appViewModel.activeBinding?.id
        appViewModel.showAgentSettings = true
    }
}
