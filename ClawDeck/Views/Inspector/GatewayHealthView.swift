import SwiftUI

/// ViewModel for the gateway health dashboard.
@Observable
@MainActor
final class GatewayHealthViewModel {

    // MARK: - Dependencies

    private weak var appViewModel: AppViewModel?

    // MARK: - State

    var statusResult: GatewayStatusResult?
    var healthResult: GatewayHealthResult?
    var isLoading = false
    var errorMessage: String?
    var autoRefresh = true
    var lastRefreshed: Date?

    private var refreshTask: Task<Void, Never>?

    // MARK: - Init

    init(appViewModel: AppViewModel?) {
        self.appViewModel = appViewModel
    }

    // MARK: - Data loading

    func load() async {
        guard let client = appViewModel?.activeClient else {
            errorMessage = "No active gateway connection"
            return
        }

        isLoading = true
        errorMessage = nil

        // Fetch status and health in parallel
        async let statusReq = client.gatewayStatus()
        async let healthReq: GatewayHealthResult? = {
            do { return try await client.gatewayHealth() }
            catch { return nil }  // health endpoint may not exist yet
        }()

        do {
            let status = try await statusReq
            let health = await healthReq
            statusResult = status
            healthResult = health
            lastRefreshed = Date()
        } catch {
            errorMessage = "Failed to load status: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Auto-refresh

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                guard !Task.isCancelled else { break }
                guard let self, self.autoRefresh else { continue }
                await self.load()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Formatting

    static func formatUptime(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        let totalSeconds = Int(ms / 1000)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    static func formatBytes(_ bytes: Int?) -> String {
        guard let bytes else { return "—" }
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }

    static func statusColor(_ status: String?) -> Color {
        switch status {
        case "ok": return .green
        case "degraded": return .yellow
        case "error": return .red
        default: return .secondary
        }
    }
}

// MARK: - View

/// Gateway status / health dashboard tab in the Inspector.
struct GatewayHealthView: View {
    @State var viewModel: GatewayHealthViewModel

    init(appViewModel: AppViewModel?) {
        _viewModel = State(initialValue: GatewayHealthViewModel(appViewModel: appViewModel))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.statusResult == nil {
                VStack {
                    Spacer()
                    ProgressView("Loading status…")
                    Spacer()
                }
            } else if let error = viewModel.errorMessage, viewModel.statusResult == nil {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await viewModel.load() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
                .padding()
            } else {
                contentView
            }
        }
        .task {
            await viewModel.load()
            viewModel.startAutoRefresh()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
    }

    // MARK: - Content

    private var contentView: some View {
        Form {
            // Gateway info
            if let status = viewModel.statusResult {
                Section("Gateway") {
                    if let version = status.version {
                        LabeledContent("Version", value: version)
                    }
                    if let commit = status.commit {
                        LabeledContent("Commit") {
                            Text(String(commit.prefix(8)))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Uptime", value: GatewayHealthViewModel.formatUptime(status.uptimeMs))
                    if let agents = status.agents {
                        LabeledContent("Agents", value: "\(agents)")
                    }
                    if let sessions = status.sessions {
                        LabeledContent("Sessions", value: "\(sessions)")
                    }
                }

                // Channels
                if let channels = status.channels, !channels.isEmpty {
                    Section("Channels") {
                        ForEach(channels) { channel in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(GatewayHealthViewModel.statusColor(channel.status))
                                    .frame(width: 8, height: 8)

                                Text(channel.label ?? channel.plugin ?? channel.id)
                                    .font(.system(size: 12, weight: .medium))

                                Spacer()

                                if let plugin = channel.plugin, channel.label != nil {
                                    Text(plugin)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // Memory
                if let mem = status.memory {
                    Section("Memory") {
                        if let rss = mem.rss {
                            LabeledContent("RSS", value: GatewayHealthViewModel.formatBytes(rss))
                        }
                        if let heapUsed = mem.heapUsed, let heapTotal = mem.heapTotal {
                            LabeledContent("Heap") {
                                Text("\(GatewayHealthViewModel.formatBytes(heapUsed)) / \(GatewayHealthViewModel.formatBytes(heapTotal))")
                                    .monospacedDigit()
                            }
                        }
                        if let external = mem.external {
                            LabeledContent("External", value: GatewayHealthViewModel.formatBytes(external))
                        }
                    }
                }
            }

            // Health components
            if let health = viewModel.healthResult, let components = health.components, !components.isEmpty {
                Section("Health Checks") {
                    ForEach(components) { component in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(GatewayHealthViewModel.statusColor(component.status))
                                .frame(width: 8, height: 8)

                            Text(component.name)
                                .font(.system(size: 12, weight: .medium))

                            Spacer()

                            if let latency = component.latencyMs {
                                Text(String(format: "%.0fms", latency))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }

                            if let message = component.message {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            // Refresh controls
            Section {
                Toggle("Auto-refresh (30s)", isOn: $viewModel.autoRefresh)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                HStack {
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        Label("Refresh Now", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isLoading)

                    Spacer()

                    if let lastRefreshed = viewModel.lastRefreshed {
                        Text("Updated \(lastRefreshed, style: .relative) ago")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
