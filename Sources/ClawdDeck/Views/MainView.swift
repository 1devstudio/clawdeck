import SwiftUI

/// Main three-column layout for the app.
struct MainView: View {
    @Bindable var appViewModel: AppViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        HStack(spacing: 0) {
            // Agent rail (leftmost)
            AgentRailView(
                profiles: appViewModel.connectionManager.profiles,
                activeProfileId: appViewModel.connectionManager.activeProfile?.id,
                connectionState: appViewModel.connectionManager.connectionState,
                onSelect: { profile in
                    Task { await appViewModel.switchAgent(profile) }
                },
                onAdd: {
                    appViewModel.showAgentSettings = true
                }
            )

            Divider()

            // Main content: sidebar + detail
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(viewModel: appViewModel.sidebarViewModel)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
            } detail: {
                if let sessionKey = appViewModel.selectedSessionKey {
                    chatArea(sessionKey: sessionKey)
                } else {
                    ContentUnavailableView(
                        "No Session Selected",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Select a session from the sidebar or create a new one.")
                    )
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                connectionStatusView

                Button {
                    appViewModel.isInspectorVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Inspector")
            }
        }
        .sheet(isPresented: $appViewModel.showAgentSettings) {
            AgentSettingsSheet(appViewModel: appViewModel)
        }
    }

    // MARK: - Chat area with optional inspector

    @ViewBuilder
    private func chatArea(sessionKey: String) -> some View {
        HStack(spacing: 0) {
            ChatView(viewModel: ChatViewModel(
                sessionKey: sessionKey,
                appViewModel: appViewModel
            ))
            .frame(maxWidth: .infinity)
            .id(sessionKey) // Stabilize: only recreate ChatView when session actually changes

            if appViewModel.isInspectorVisible, let session = appViewModel.selectedSession {
                Divider()
                InspectorView(session: session, appViewModel: appViewModel)
                    .frame(width: 280)
            }
        }
    }

    // MARK: - Connection status

    @ViewBuilder
    private var connectionStatusView: some View {
        let state = appViewModel.connectionManager.connectionState
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor(for: state))
                .frame(width: 8, height: 8)
            Text(state.rawValue.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }

    private func statusColor(for state: ConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected: return .red
        }
    }
}
