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

    /// The active chat view model (if a session is selected).
    private var activeChatVM: ChatViewModel? {
        guard let key = appViewModel.selectedSessionKey else { return nil }
        return appViewModel.chatViewModel(for: key)
    }

    private let sidebarMinWidth: CGFloat = 200
    private let sidebarMaxWidth: CGFloat = 400
    private let railWidth: CGFloat = 60

    var body: some View {
        HStack(spacing: 0) {
            // Agent rail (outer shell)
            AgentRailView(
                bindings: appViewModel.gatewayManager.sortedAgentBindings,
                activeBindingId: appViewModel.activeBinding?.id,
                gatewayManager: appViewModel.gatewayManager,
                onSelect: { binding in
                    Task { await appViewModel.switchAgent(binding) }
                },
                onAddBinding: { binding in
                    Task { await appViewModel.switchAgent(binding) }
                },
                onConnectNewGateway: {
                    appViewModel.showGatewayConnectionSheet = true
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
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
            // Search bar — searches messages in the active session
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)

                    TextField("Search messages…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit {
                            activeChatVM?.nextMatch()
                        }

                    if let vm = activeChatVM, !searchText.isEmpty {
                        let count = vm.searchMatchIds.count
                        if count > 0 {
                            Text("\(vm.currentMatchIndex + 1)/\(count)")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)

                            Button {
                                vm.previousMatch()
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)

                            Button {
                                vm.nextMatch()
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("No results")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 500)
                .focusEffectDisabled()
                .onChange(of: searchText) { _, newValue in
                    activeChatVM?.searchQuery = newValue
                    activeChatVM?.currentMatchIndex = 0
                }
                .onChange(of: appViewModel.selectedSessionKey) { _, _ in
                    searchText = ""
                    activeChatVM?.searchQuery = ""
                }
            }

            // Right-aligned controls — separate items, no shared background
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionStatusColor)
                        .frame(width: 7, height: 7)
                    Text(activeGatewayConnectionState.rawValue.capitalized)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    appViewModel.isInspectorVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Toggle Inspector (⌘⇧I)")
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
        .sheet(isPresented: $appViewModel.showGatewayConnectionSheet) {
            ConnectionSetupView(appViewModel: appViewModel)
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

    /// Connection state for the active binding's gateway.
    private var activeGatewayConnectionState: ConnectionState {
        guard let binding = appViewModel.activeBinding else { return .disconnected }
        return appViewModel.gatewayManager.connectionState(for: binding.gatewayId)
    }
    
    private var connectionStatusColor: Color {
        switch activeGatewayConnectionState {
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
