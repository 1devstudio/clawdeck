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
    var isLoading = false

    /// Currently hovered session (for context menu).
    var hoveredSessionKey: String?

    /// Session being renamed.
    var renamingSessionKey: String?
    var renameText = ""

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

    /// Sessions grouped by time period.
    var groupedSessions: [(title: String, sessions: [Session])] {
        let sorted = filteredSessions.sorted { ($0.updatedAt) > ($1.updatedAt) }
        let calendar = Calendar.current
        let now = Date()

        var today: [Session] = []
        var yesterday: [Session] = []
        var thisWeek: [Session] = []
        var older: [Session] = []

        for session in sorted {
            if calendar.isDateInToday(session.updatedAt) {
                today.append(session)
            } else if calendar.isDateInYesterday(session.updatedAt) {
                yesterday.append(session)
            } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
                      session.updatedAt > weekAgo {
                thisWeek.append(session)
            } else {
                older.append(session)
            }
        }

        var groups: [(title: String, sessions: [Session])] = []
        if !today.isEmpty { groups.append(("Today", today)) }
        if !yesterday.isEmpty { groups.append(("Yesterday", yesterday)) }
        if !thisWeek.isEmpty { groups.append(("This Week", thisWeek)) }
        if !older.isEmpty { groups.append(("Older", older)) }
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
        isLoading = true
        await appViewModel.refreshSessions()
        isLoading = false
    }

    /// Select a session.
    func selectSession(_ key: String) async {
        await appViewModel.selectSession(key)
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
}
