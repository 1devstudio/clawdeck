import SwiftUI

/// Channels list view — displayed as a tab in the Inspector panel.
struct ChannelsView: View {
    @Bindable var viewModel: ChannelsViewModel

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.channels.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.channels.isEmpty {
                errorView(error)
            } else if viewModel.channels.isEmpty {
                emptyView
            } else {
                channelsList
            }
        }
        .task {
            await viewModel.loadChannels()
        }
        .sheet(isPresented: .constant(viewModel.loginChannelId != nil)) {
            QRLoginSheet(viewModel: viewModel)
        }
    }

    // MARK: - Channels list

    private var channelsList: some View {
        List {
            ForEach(viewModel.channels) { channel in
                ChannelRow(
                    channel: channel,
                    isExpanded: viewModel.expandedChannelId == channel.id,
                    onToggleExpand: { viewModel.toggleExpanded(channel.id) },
                    onLogin: { Task { await viewModel.startLogin(channel: channel.id) } },
                    onLogout: { accountId in Task { await viewModel.logout(channel: channel.id, accountId: accountId) } }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.loadChannels()
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Loading channels…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.loadChannels() }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No Channels",
            systemImage: "antenna.radiowaves.left.and.right",
            description: Text("No channels found on this gateway.")
        )
    }
}

// MARK: - Channel Row

/// A single channel row with expandable details.
struct ChannelRow: View {
    let channel: ChannelInfo
    let isExpanded: Bool
    var onToggleExpand: () -> Void
    var onLogin: () -> Void
    var onLogout: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row — clickable to expand
            Button(action: onToggleExpand) {
                mainRow
            }
            .buttonStyle(.plain)

            // Expanded details
            if isExpanded {
                expandedDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    // MARK: - Main row

    private var mainRow: some View {
        HStack(spacing: 8) {
            // Status indicator
            statusIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    // Icon
                    Image(systemName: channel.systemImage)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    // Detail label
                    if let detail = channel.detailLabel {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Status badges
            statusBadges

            // Chevron
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        if !channel.configured {
            return .gray.opacity(0.4)
        } else if channel.connected {
            return .green
        } else if channel.enabled {
            return .orange
        } else {
            return .gray.opacity(0.6)
        }
    }

    private var statusBadges: some View {
        HStack(spacing: 2) {
            if channel.connected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.green)
            } else if channel.loggedIn {
                Image(systemName: "person.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Expanded details

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.vertical, 4)

            // Status overview
            statusOverview

            // Accounts list
            if !channel.accounts.isEmpty {
                accountsList
            }

            // Error display
            if let error = channel.error {
                errorDisplay(error)
            }

            // Action buttons
            actionButtons
        }
        .padding(.leading, 24)
        .padding(.trailing, 4)
        .padding(.bottom, 4)
    }

    private var statusOverview: some View {
        Grid(alignment: .leading, verticalSpacing: 4) {
            GridRow {
                Text("Status")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 65, alignment: .leading)
                
                HStack(spacing: 4) {
                    if channel.connected {
                        Text("Connected")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    } else if channel.configured {
                        Text("Configured")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not configured")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !channel.accounts.isEmpty {
                GridRow {
                    Text("Accounts")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 65, alignment: .leading)
                    Text("\(channel.accounts.count)")
                        .font(.system(size: 11))
                }
            }

            if let lastInbound = channel.lastInboundAt {
                GridRow {
                    Text("Last msg")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 65, alignment: .leading)
                    Text(formatRelativeDate(lastInbound))
                        .font(.system(size: 11))
                }
            }
        }
    }

    private var accountsList: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Accounts")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(channel.accounts) { account in
                AccountRow(
                    account: account,
                    onLogout: { onLogout(account.accountId) }
                )
            }
        }
    }

    private func errorDisplay(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Error")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.red)
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .lineLimit(4)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.red.opacity(0.1))
                )
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if channel.supportsLogin && !channel.connected {
                Button {
                    onLogin()
                } label: {
                    Label("Login", systemImage: "qrcode")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if channel.connected {
                Button {
                    onLogout(nil)
                } label: {
                    Label("Logout", systemImage: "power")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()
        }
        .padding(.top, 4)
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Account Row

/// A single account within a channel.
struct AccountRow: View {
    let account: ChannelAccountInfo
    var onLogout: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accountStatusColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(account.accountId)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if account.connected {
                        Text("Connected")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                    } else if account.loggedIn {
                        Text("Logged in")
                            .font(.system(size: 9))
                            .foregroundStyle(.blue)
                    } else if account.configured {
                        Text("Configured")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not configured")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                    if let lastInbound = account.lastInboundAt {
                        Text("·")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(formatRelativeDate(lastInbound))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if account.connected || account.loggedIn {
                Button {
                    onLogout()
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary.opacity(0.3))
        )
    }

    private var accountStatusColor: Color {
        if account.connected {
            return .green
        } else if account.loggedIn {
            return .blue
        } else if account.configured {
            return .orange
        } else {
            return .gray.opacity(0.4)
        }
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d"
        }
    }
}

// MARK: - QR Login Sheet

/// Sheet for displaying QR code during login process.
struct QRLoginSheet: View {
    @Bindable var viewModel: ChannelsViewModel

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("WhatsApp Login")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    viewModel.cancelLogin()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

            if let qrDataURL = viewModel.qrCodeDataURL {
                QRCodeView(dataURL: qrDataURL)
            } else if viewModel.isLoginInProgress {
                ProgressView()
                    .controlSize(.large)
            }

            if let statusMessage = viewModel.loginStatusMessage {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !viewModel.isLoginInProgress {
                Button("Close") {
                    viewModel.cancelLogin()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 350, height: 400)
    }
}

// MARK: - QR Code View

/// Displays a QR code from a base64 data URL.
struct QRCodeView: View {
    let dataURL: String

    var body: some View {
        Group {
            if let image = createImage(from: dataURL) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.gray.opacity(0.2))
                    .frame(width: 200, height: 200)
                    .overlay(
                        Text("Failed to load QR code")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    )
            }
        }
    }

    private func createImage(from dataURL: String) -> NSImage? {
        // Handle data URL format: data:image/png;base64,iVBORw0KGgo...
        guard let range = dataURL.range(of: ","),
              let data = Data(base64Encoded: String(dataURL[range.upperBound...])) else {
            return nil
        }
        return NSImage(data: data)
    }
}