import SwiftUI

/// Left sidebar showing agents and sessions.
struct SidebarView: View {
    @Bindable var viewModel: SidebarViewModel

    var body: some View {
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
        .searchable(text: $viewModel.searchText, prompt: "Search sessions")
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
