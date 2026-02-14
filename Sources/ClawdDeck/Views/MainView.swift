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
        VStack(spacing: 0) {
            // ── Top Bar (full width) ──
            TopBarView(
                searchText: $searchText,
                connectionState: appViewModel.connectionManager.connectionState,
                isInspectorVisible: $appViewModel.isInspectorVisible,
                onSettings: { appViewModel.showAgentSettings = true }
            )

            // ── Body: Rail + Inner Panel ──
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

                // Inner panel (sidebar + content)
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
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .overlay(alignment: .top) {
            // Window drag area (invisible, covers top bar)
            Color.clear
                .frame(height: 38)
                .windowDraggable()
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

    private var emptyState: some View {
        ContentUnavailableView(
            "No Session Selected",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("Select a session from the sidebar or create a new one.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Top Bar

/// Full-width top bar with search, connection status, and window controls.
struct TopBarView: View {
    @Binding var searchText: String
    let connectionState: ConnectionState
    @Binding var isInspectorVisible: Bool
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Spacer for traffic light buttons (close/min/max are ~78px wide)
            Color.clear
                .frame(width: 78, height: 1)

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))

                TextField("Search sessions…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 400)

            Spacer()

            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(connectionState.rawValue.capitalized)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Inspector toggle
            Button {
                isInspectorVisible.toggle()
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle Inspector (⌘⇧I)")

            // Settings
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.ultraThinMaterial)
    }

    private var statusColor: Color {
        switch connectionState {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected: return .red
        }
    }
}

// MARK: - Window Draggable modifier

extension View {
    /// Makes a view act as a window drag area (title bar replacement).
    func windowDraggable() -> some View {
        self.overlay(WindowDragView())
    }
}

/// An NSView-based drag area for the custom title bar.
struct WindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WindowDragNSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class WindowDragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
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
