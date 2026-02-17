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
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @State private var sidebarWidth: CGFloat = 260
    @State private var searchText: String = ""

    /// Tracks the last sidebar width before collapsing, so we can restore it.
    @State private var sidebarWidthBeforeCollapse: CGFloat = 260

    /// Focus state for the toolbar search bar.
    @FocusState private var isSearchBarFocused: Bool

    /// The active chat view model (if a session is selected).
    private var activeChatVM: ChatViewModel? {
        guard let key = appViewModel.selectedSessionKey else { return nil }
        return appViewModel.chatViewModel(for: key)
    }

    private let sidebarMinWidth: CGFloat = 200
    private let sidebarMaxWidth: CGFloat = 400
    private let railWidth: CGFloat = 60

    /// The color scheme the chrome (toolbar area) should use.
    private var chromeScheme: ColorScheme {
        if !appViewModel.themeConfig.chromeUsesSystem {
            return Color(hex: appViewModel.themeConfig.chromeColorHex).preferredColorScheme
        }
        // Derive the scheme from the explicit appearance mode so toolbar colors
        // update immediately on picker change. For the "system" case, read the
        // OS dark-mode setting directly because @Environment(\.colorScheme) can
        // be stale after switching from an explicit mode to .preferredColorScheme(nil).
        switch AppearanceMode(rawValue: appearanceModeRaw) ?? .system {
        case .light:  return .light
        case .dark:   return .dark
        case .system:
            let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            return isDark ? .dark : .light
        }
    }

    /// Toolbar foreground matching `.secondary` for the chrome's color scheme.
    private var chromeSecondary: Color {
        chromeScheme == .dark
            ? Color.white.opacity(0.55)
            : Color.black.opacity(0.45)
    }

    /// Toolbar foreground matching `.tertiary` for the chrome's color scheme.
    private var chromeTertiary: Color {
        chromeScheme == .dark
            ? Color.white.opacity(0.35)
            : Color.black.opacity(0.3)
    }

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
                .background {
                    InnerPanelBackground()
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                )
                .padding(.trailing, 12)
                .padding(.bottom, 12)
        }
        .background(appViewModel.themeConfig.chromeColor)
        .chromeColorScheme(appViewModel.themeConfig, systemScheme: systemColorScheme)
        .tint(appViewModel.customAccentColor)
        .environment(\.themeColor, appViewModel.customAccentColor ?? .accentColor)
        .environment(\.themeConfig, appViewModel.themeConfig)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbar {
            // Search bar — searches messages in the active session
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(chromeTertiary)

                    TextField("", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(chromeScheme == .dark ? .white : .black)
                        .overlay(alignment: .leading) {
                            if searchText.isEmpty {
                                Text("Search messages…")
                                    .font(.system(size: 13))
                                    .foregroundStyle(chromeTertiary)
                                    .allowsHitTesting(false)
                            }
                        }
                        .focused($isSearchBarFocused)
                        .onSubmit {
                            activeChatVM?.nextMatch()
                        }

                    if let vm = activeChatVM, !searchText.isEmpty {
                        let count = vm.searchMatchIds.count
                        if count > 0 {
                            Text("\(vm.currentMatchIndex + 1)/\(count)")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(chromeSecondary)

                            Button {
                                vm.previousMatch()
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(chromeSecondary)
                            }
                            .buttonStyle(.plain)

                            Button {
                                vm.nextMatch()
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(chromeSecondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("No results")
                                .font(.system(size: 11))
                                .foregroundStyle(chromeSecondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(chromeSecondary.opacity(0.15))
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
                    Text(appViewModel.activeConnectionState.rawValue.capitalized)
                        .font(.system(size: 11))
                        .foregroundStyle(chromeSecondary)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    appViewModel.isInspectorVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13))
                        .foregroundStyle(chromeSecondary)
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
        // Sidebar collapse/expand driven by AppViewModel
        .onChange(of: appViewModel.isSidebarCollapsed) { _, collapsed in
            withAnimation(.easeInOut(duration: 0.2)) {
                if collapsed {
                    // Remember the current width so we can restore it later.
                    sidebarWidthBeforeCollapse = sidebarWidth
                } else {
                    // Restore the previous width when expanding.
                    sidebarWidth = sidebarWidthBeforeCollapse
                }
            }
        }
        // Focus search bar when triggered via ⌘K
        .onChange(of: appViewModel.focusSearchBarTrigger) { _, _ in
            isSearchBarFocused = true
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
            // Sidebar — Liquid Glass panel (hidden when collapsed)
            if !appViewModel.isSidebarCollapsed {
                SidebarView(viewModel: appViewModel.sidebarViewModel)
                    .frame(width: sidebarWidth)
                    .background {
                        ThemedSidebarBackground()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .adaptiveColorScheme(
                        style: appViewModel.themeConfig.sidebarStyle,
                        background: appViewModel.themeConfig.sidebarColor,
                        systemScheme: systemColorScheme
                    )
                    .overlay(alignment: .trailing) {
                        // Invisible trailing-edge drag handle for resizing
                        Color.clear
                            .frame(width: 6)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.resizeLeftRight.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .gesture(
                                DragGesture(coordinateSpace: .global)
                                    .onChanged { value in
                                        let newWidth = value.location.x - railWidth - 1
                                        sidebarWidth = min(max(newWidth, sidebarMinWidth), sidebarMaxWidth)
                                    }
                            )
                    }
                    .padding(12)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Chat area
            if let sessionKey = appViewModel.selectedSessionKey {
                chatArea(sessionKey: sessionKey)
            } else {
                emptyState
                    .environment(\.colorScheme, systemColorScheme)
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
                .environment(\.colorScheme, systemColorScheme)

            if appViewModel.isInspectorVisible, let session = appViewModel.selectedSession {
                Divider()
                InspectorView(session: session, appViewModel: appViewModel)
                    .frame(width: 280)
                    .environment(\.colorScheme, chromeScheme)
            }
        }
    }

    private var connectionStatusColor: Color {
        switch appViewModel.activeConnectionState {
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
        .padding(32)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
