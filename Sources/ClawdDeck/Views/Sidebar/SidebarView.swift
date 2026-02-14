import SwiftUI

/// Left sidebar showing agents and sessions.
struct SidebarView: View {
    @Bindable var viewModel: SidebarViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header: agent name + action buttons
            HStack(spacing: 8) {
                Text(viewModel.agentDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Button {
                    viewModel.showAgentSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")

                Button {
                    Task { await viewModel.refreshSessions() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh")
                .disabled(viewModel.isLoading)

                Button {
                    Task { await viewModel.createNewSession() }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Session (⌘N)")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 11))
                TextField("Search sessions", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

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
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .controlBackgroundColor))
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
        .onChange(of: viewModel.selectedSessionKey) { _, newKey in
            if let key = newKey {
                Task { await viewModel.selectSession(key) }
            }
        }
    }
}
