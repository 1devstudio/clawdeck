import SwiftUI

/// Left sidebar showing agents and sessions.
struct SidebarView: View {
    @Bindable var viewModel: SidebarViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Search bar + settings header
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                    TextField("Search sessions", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(6)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Button {
                    viewModel.showAgentSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Agent Settings")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List(selection: $viewModel.selectedSessionKey) {
                // Sessions grouped by time
                ForEach(viewModel.groupedSessions, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.sessions) { session in
                            SessionRow(
                                session: session,
                                isRenaming: viewModel.renamingSessionKey == session.key,
                                renameText: $viewModel.renameText,
                                onCommitRename: {
                                    Task { await viewModel.commitRename() }
                                },
                                onCancelRename: {
                                    viewModel.cancelRename()
                                }
                            )
                            .tag(session.key)
                            .contextMenu {
                                Button("Rename…") {
                                    viewModel.beginRename(session.key)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    Task { await viewModel.deleteSession(session.key) }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .overlay {
            if viewModel.filteredSessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "tray",
                    description: Text("Start a conversation or connect to a gateway.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await viewModel.createNewSession() }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("New Session (⌘N)")
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    Task { await viewModel.refreshSessions() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                .disabled(viewModel.isLoading)
            }
        }
        .onChange(of: viewModel.selectedSessionKey) { _, newKey in
            if let key = newKey {
                Task { await viewModel.selectSession(key) }
            }
        }
    }
}
