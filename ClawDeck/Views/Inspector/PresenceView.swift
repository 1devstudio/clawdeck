import SwiftUI

/// Displays connected gateway instances (presence list) in the inspector panel.
struct PresenceView: View {
    let appViewModel: AppViewModel

    @State private var instances: [PresenceInstance] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentConnId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Instances")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await loadPresence() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .help("Refresh")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if isLoading && instances.isEmpty {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Spacer()
            } else if let error = errorMessage, instances.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else if instances.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "network.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No instances connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(instances) { instance in
                            InstanceRow(
                                instance: instance,
                                isCurrentDevice: instance.id == currentConnId
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
        }
        .task {
            await loadPresence()
        }
    }

    private func loadPresence() async {
        guard let binding = appViewModel.activeBinding,
              let client = appViewModel.gatewayManager.client(for: binding.gatewayId) else {
            errorMessage = "Not connected"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // Fetch our connId from the handshake result
            let hello = await client.helloResult
            currentConnId = hello?.server.connId

            let result = try await client.systemPresence()
            instances = result.instances.sorted { lhs, rhs in
                // Current device first, then by connectedAt descending
                if lhs.id == currentConnId { return true }
                if rhs.id == currentConnId { return false }
                return (lhs.connectedAt ?? 0) > (rhs.connectedAt ?? 0)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Instance Row

private struct InstanceRow: View {
    let instance: PresenceInstance
    let isCurrentDevice: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                // Client name + this-device badge
                HStack(spacing: 4) {
                    Image(systemName: platformIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text(instance.client ?? "Unknown client")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    if isCurrentDevice {
                        Text("THIS")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }

                // Version + role
                HStack(spacing: 6) {
                    if let version = instance.version {
                        Text("v\(version)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    if let role = instance.role {
                        Text(role)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(roleBadgeColor.opacity(0.12))
                            .foregroundStyle(roleBadgeColor)
                            .clipShape(Capsule())
                    }
                }

                // Connection duration
                if let connectedAt = instance.connectedAt {
                    Text(connectionDuration(since: connectedAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrentDevice
                      ? Color.accentColor.opacity(0.06)
                      : Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }

    private var statusColor: Color {
        switch instance.status {
        case "online", "connected": return .green
        case "idle": return .yellow
        default: return .green.opacity(0.6)
        }
    }

    private var platformIcon: String {
        switch instance.platform?.lowercased() {
        case "macos", "darwin": return "laptopcomputer"
        case "linux": return "server.rack"
        case "windows": return "desktopcomputer"
        case "ios": return "iphone"
        case "android": return "smartphone"
        case "web", "browser": return "globe"
        default: return "desktopcomputer"
        }
    }

    private var roleBadgeColor: Color {
        switch instance.role?.lowercased() {
        case "operator": return .blue
        case "admin": return .purple
        case "agent": return .orange
        default: return .secondary
        }
    }

    private func connectionDuration(since epochMs: Double) -> String {
        let connectedDate = Date(timeIntervalSince1970: epochMs / 1000)
        let interval = Date().timeIntervalSince(connectedDate)

        if interval < 60 {
            return "Connected just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "Connected \(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            let mins = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            return mins > 0
                ? "Connected \(hours)h \(mins)m ago"
                : "Connected \(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)
            return hours > 0
                ? "Connected \(days)d \(hours)h ago"
                : "Connected \(days)d ago"
        }
    }
}
