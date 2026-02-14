import SwiftUI

/// Main layout mimicking Slack's structure:
///
/// ```
/// ┌──────────────────────────────────────────────────┐
/// │  🔍 Search                          status   ⚙  │  ← Top Bar (full width)
/// ├──────┬───────────────────────────────────────────┤
/// │      │┌─────────────────────────────────────────┐│
/// │  🤖  ││ Sessions list  │  Chat content          ││
/// │  🤖  ││               │                         ││  ← Inner Panel
/// │      ││               │  [Composer]             ││
/// │  +   │└─────────────────────────────────────────┘│
/// └──────┴───────────────────────────────────────────┘
/// ```
///
/// The **agent rail + top bar** are the outer shell (darkest background).
/// The **sidebar + content** sit inside an inset panel with a lighter background.
struct MainView: View {
    @Bindable var appViewModel: AppViewModel
    @State private var sidebarWidth: CGFloat = 260
    @State private var searchText: String = ""

    private let sidebarMinWidth: CGFloat = 200
    private let sidebarMaxWidth: CGFloat = 400
    private let railWidth: CGFloat = 60

    var body: some View {
        HStack(spacing: 0) {
            // Agent rail (outer shell)
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

            // Inner panel (sidebar + content) — inset with border like Slack
            innerPanel
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 8,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 8,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                )
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .toolbar {
            // Search bar — centered via .principal
            ToolbarItem(placement: .principal) {
                TextField("Search sessions…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .padding(.horizontal, 8)
                    .frame(width: 500)
            }

            // Right-aligned controls — plain style, no button chrome
            ToolbarItemGroup(placement: .primaryAction) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionStatusColor)
                        .frame(width: 7, height: 7)
                    Text(appViewModel.connectionManager.connectionState.rawValue.capitalized)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Button {
                    appViewModel.isInspectorVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Toggle Inspector (⌘⇧I)")

                Button {
                    appViewModel.showAgentSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }
        }
        .onAppear {
            // Configure the window title bar to be transparent
            DispatchQueue.main.async {
                if let window = NSApp.windows.first {
                    AppDelegate.configureWindowTitleBar(window)
                }
            }
        }
        .sheet(isPresented: $appViewModel.showAgentSettings, onDismiss: {
            appViewModel.editingAgentProfileId = nil
        }) {
            AgentSettingsSheet(appViewModel: appViewModel)
        }
    }

    // MARK: - Inner Panel (Sidebar + Content)

    private var innerPanel: some View {
        HStack(spacing: 0) {
            // Sidebar
            SidebarView(viewModel: appViewModel.sidebarViewModel)
                .frame(width: sidebarWidth)

            // Draggable resize handle
            ResizeHandle()
                .gesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                            let newWidth = value.location.x - railWidth - 1
                            sidebarWidth = min(max(newWidth, sidebarMinWidth), sidebarMaxWidth)
                        }
                )

            // Chat area
            if let sessionKey = appViewModel.selectedSessionKey {
                chatArea(sessionKey: sessionKey)
            } else {
                emptyState
            }
        }
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

    private var connectionStatusColor: Color {
        switch appViewModel.connectionManager.connectionState {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected: return .red
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Session Selected",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("Select a session from the sidebar or create a new one.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
