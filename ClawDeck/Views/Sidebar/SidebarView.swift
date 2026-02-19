import SwiftUI

/// Custom section header with optional leading icon and inter-section spacing.
private struct SectionHeaderView: View {
    let title: String
    let isFirst: Bool
    /// When true, shows the "History" parent header above the sub-group title.
    var showHistoryParent: Bool = false

    private var iconName: String? {
        switch title {
        case "Starred": "star.fill"
        case "Active":  "circle.fill"
        default:        nil
        }
    }

    private var iconColor: Color {
        switch title {
        case "Starred": .yellow
        case "Active":  .green
        default:        .secondary
        }
    }

    /// Whether this title is a History sub-group.
    private var isSubgroup: Bool {
        SidebarViewModel.historySubgroups.contains(title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showHistoryParent {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                    Text("HISTORY")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.3)
                }
                .padding(.top, isFirst ? 0 : 12)
                .padding(.bottom, 4)
            }

            if isSubgroup {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .tracking(0.2)
                    .padding(.top, showHistoryParent ? 0 : 8)
                    .padding(.bottom, 2)
            } else {
                HStack(spacing: 4) {
                    if let iconName {
                        Image(systemName: iconName)
                            .font(.system(size: 7))
                            .foregroundStyle(iconColor)
                    }
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.3)
                }
                .padding(.top, isFirst ? 0 : 12)
                .padding(.bottom, 4)
            }
        }
    }
}

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
            .background(.ultraThinMaterial.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            List(selection: $viewModel.selectedSessionKey) {
                // Sessions grouped by time
                ForEach(Array(viewModel.groupedSessions.enumerated()), id: \.element.title) { index, group in
                    Section {
                        ForEach(group.sessions) { session in
                            SessionRow(
                                session: session,
                                isStarred: viewModel.isStarred(session.key),
                                isLoadingHistory: viewModel.isLoadingHistory(session.key),
                                isRenaming: viewModel.renamingSessionKey == session.key,
                                renameText: $viewModel.renameText,
                                onCommitRename: {
                                    Task { await viewModel.commitRename() }
                                },
                                onCancelRename: {
                                    viewModel.cancelRename()
                                },
                                onDoubleClickTitle: {
                                    viewModel.beginRename(session.key)
                                }
                            )
                            .tag(session.key)
                            .listRowBackground(Color.clear)
                            .contextMenu {
                                Button {
                                    viewModel.toggleStar(session.key)
                                } label: {
                                    if viewModel.isStarred(session.key) {
                                        Label("Unstar", systemImage: "star.slash")
                                    } else {
                                        Label("Star", systemImage: "star")
                                    }
                                }

                                Button("Rename…") {
                                    viewModel.beginRename(session.key)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    Task { await viewModel.deleteSession(session.key) }
                                }
                            }
                        }
                    } header: {
                        SectionHeaderView(
                            title: group.title,
                            isFirst: index == 0,
                            showHistoryParent: SidebarViewModel.historySubgroups.contains(group.title)
                                && (index == 0 || !SidebarViewModel.historySubgroups.contains(viewModel.groupedSessions[index - 1].title))
                        )
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .alternatingRowBackgrounds(.disabled)
        }
        .overlay {
            if viewModel.filteredSessions.isEmpty && !viewModel.hasLoadedSessions {
                ContentUnavailableView {
                    Label {
                        Text("Loading Sessions")
                    } icon: {
                        ProgressView()
                            .controlSize(.large)
                    }
                } description: {
                    Text("Fetching sessions from gateway…")
                }
            } else if viewModel.filteredSessions.isEmpty {
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
