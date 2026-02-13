import SwiftUI

/// Main three-column layout for the app.
struct MainView: View {
    @Bindable var appViewModel: AppViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(viewModel: SidebarViewModel(appViewModel: appViewModel))
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
        } content: {
            if let sessionKey = appViewModel.selectedSessionKey {
                ChatView(viewModel: ChatViewModel(
                    sessionKey: sessionKey,
                    appViewModel: appViewModel
                ))
                .navigationSplitViewColumnWidth(min: 400, ideal: 600, max: .infinity)
            } else {
                ContentUnavailableView(
                    "No Session Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select a session from the sidebar or create a new one.")
                )
            }
        } detail: {
            if appViewModel.isInspectorVisible, let session = appViewModel.selectedSession {
                InspectorView(session: session, appViewModel: appViewModel)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 350)
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
        .sheet(isPresented: $appViewModel.showConnectionSetup) {
            ConnectionSetupView(appViewModel: appViewModel)
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
    }

    private func statusColor(for state: ConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected: return .red
        }
    }
}
