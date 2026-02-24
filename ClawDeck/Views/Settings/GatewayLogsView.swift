import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GatewayLogsView: View {
    @State private var viewModel = GatewayLogsViewModel()

    /// The gateway client to use — injected from the app scene.
    var client: GatewayClient?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Level filter
                Picker("Level", selection: $viewModel.selectedLevel) {
                    ForEach(GatewayLogLevel.allCases) { level in
                        Label(level.displayName, systemImage: level.sfSymbol)
                            .tag(level)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)

                // Category filter
                Picker("Category", selection: $viewModel.selectedCategory) {
                    ForEach(viewModel.categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search logs...", text: $viewModel.searchText)
                }
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)

                // Auto-scroll toggle
                Toggle("Auto-scroll", isOn: $viewModel.autoScroll)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Divider()
                    .frame(height: 20)

                // Action buttons
                Button("Clear") {
                    viewModel.clearLogs()
                }
                .buttonStyle(.bordered)

                Button("Export") {
                    exportLogs()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.regularMaterial)

            Divider()

            // Error banner
            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.errorMessage = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.08))

                Divider()
            }

            // Log entries
            if viewModel.filteredEntries.isEmpty && viewModel.entries.isEmpty {
                ContentUnavailableView {
                    Label("No Gateway Logs", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Gateway log entries will appear here once the connection is active.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.filteredEntries) { entry in
                                GatewayLogEntryRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .background(.regularMaterial)
                    .onChange(of: viewModel.filteredEntries.count) { _, _ in
                        if viewModel.autoScroll, let lastEntry = viewModel.filteredEntries.last {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(lastEntry.id, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        if viewModel.autoScroll, let lastEntry = viewModel.filteredEntries.last {
                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .navigationTitle("Gateway Logs")
        .frame(minWidth: 800, minHeight: 500)
        .onAppear {
            viewModel.client = client
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    private func exportLogs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "gateway-logs-\(Int(Date().timeIntervalSince1970)).txt"
        savePanel.title = "Export Gateway Logs"

        savePanel.begin { result in
            guard result == .OK, let url = savePanel.url else { return }

            let logsContent = viewModel.exportLogs()

            do {
                try logsContent.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                AppLogger.error("Failed to export gateway logs: \(error.localizedDescription)", category: "GatewayLogs")
            }
        }
    }
}

struct GatewayLogEntryRow: View {
    let entry: GatewayLogEntry

    private var level: GatewayLogLevel {
        GatewayLogLevel.from(entry.level)
    }

    private var formattedTimestamp: String {
        guard let ts = entry.timestamp else { return "—" }
        // Try to format nicely; fall back to raw string
        if let ms = Double(ts) {
            let date = Date(timeIntervalSince1970: ms / 1000)
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter.string(from: date)
        }
        // ISO 8601 — extract time portion
        if ts.count > 11 && ts.contains("T") {
            let parts = ts.split(separator: "T")
            if parts.count == 2 {
                let timePart = String(parts[1]).replacingOccurrences(of: "Z", with: "")
                // Trim to HH:mm:ss.SSS
                let components = timePart.prefix(12)
                return String(components)
            }
        }
        return String(ts.prefix(12))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp
            Text(formattedTimestamp)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            // Level badge
            HStack(spacing: 4) {
                Image(systemName: level.sfSymbol)
                    .foregroundStyle(level.color)
                    .font(.caption)
                Text(level.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(level.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(level.color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(width: 80)

            // Category tag
            Text(entry.category ?? "—")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: 80)

            // Message
            Text(entry.message ?? "")
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    GatewayLogsView()
}
