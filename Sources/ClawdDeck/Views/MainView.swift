import SwiftUI

/// Main three-column layout for the app.
struct MainView: View {
    @Bindable var appViewModel: AppViewModel
    @State private var sidebarWidth: CGFloat = 260

    private let sidebarMinWidth: CGFloat = 200
    private let sidebarMaxWidth: CGFloat = 400

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

            // Sidebar (always visible, resizable)
            SidebarView(viewModel: appViewModel.sidebarViewModel)
                .frame(width: sidebarWidth)

            // Draggable resize handle
            ResizeHandle()
                .gesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                            // The rail is 60pt + 1pt divider, so offset from leading edge
                            let newWidth = value.location.x - 61
                            sidebarWidth = min(max(newWidth, sidebarMinWidth), sidebarMaxWidth)
                        }
                )

            // Detail area
            if let sessionKey = appViewModel.selectedSessionKey {
                chatArea(sessionKey: sessionKey)
            } else {
                ContentUnavailableView(
                    "No Session Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select a session from the sidebar or create a new one.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(activeAgentName)
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
        .sheet(isPresented: $appViewModel.showAgentSettings, onDismiss: {
            appViewModel.editingAgentProfileId = nil
        }) {
            AgentSettingsSheet(appViewModel: appViewModel)
        }
    }

    /// Display name of the currently active agent (connection profile).
    private var activeAgentName: String {
        appViewModel.connectionManager.activeProfile?.displayName ?? ""
    }

    // MARK: - Chat area with optional inspector

    @ViewBuilder
    private func chatArea(sessionKey: String) -> some View {
        HStack(spacing: 0) {
            ChatView(viewModel: appViewModel.chatViewModel(for: sessionKey))
            .frame(maxWidth: .infinity)
            .id(sessionKey)

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

// MARK: - Resize Handle

/// Thin draggable divider between the sidebar and detail area.
private struct ResizeHandle: View {
    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(isHovering ? Color.accentColor.opacity(0.4) : Color.clear)
            .frame(width: 5)
            .overlay(
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
