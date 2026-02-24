import SwiftUI
import Foundation

/// Log level filter for gateway logs — maps to gateway level strings.
enum GatewayLogLevel: String, CaseIterable, Identifiable {
    case debug = "debug"
    case info = "info"
    case warn = "warn"
    case error = "error"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .warn: return "Warning"
        case .error: return "Error"
        }
    }

    var color: Color {
        switch self {
        case .debug: return .secondary
        case .info: return .blue
        case .warn: return .orange
        case .error: return .red
        }
    }

    var sfSymbol: String {
        switch self {
        case .debug: return "hammer"
        case .info: return "info.circle"
        case .warn: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }

    var priority: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warn: return 2
        case .error: return 3
        }
    }

    /// Map a raw gateway level string to this enum, defaulting to debug.
    static func from(_ raw: String?) -> GatewayLogLevel {
        guard let raw else { return .debug }
        return GatewayLogLevel(rawValue: raw.lowercased()) ?? .debug
    }
}

/// ViewModel managing gateway log polling, filtering, and state.
@Observable
@MainActor
final class GatewayLogsViewModel {
    // MARK: - Published state

    var entries: [GatewayLogEntry] = []
    var selectedLevel: GatewayLogLevel = .debug
    var selectedCategory: String = "All"
    var searchText: String = ""
    var autoScroll: Bool = true
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Dependencies

    /// The gateway client to poll — set externally before starting.
    var client: GatewayClient?

    // MARK: - Private

    private var pollingTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 5.0
    private let maxEntries = 5000

    /// Epoch ms of the latest entry we've received — used for `since` param.
    private var latestTimestampMs: Double?

    // MARK: - Computed

    var categories: [String] {
        let allCategories = Set(entries.compactMap { $0.category })
        return ["All"] + Array(allCategories).sorted()
    }

    var filteredEntries: [GatewayLogEntry] {
        entries
            .filter { entry in
                // Filter by level (show selected level and above)
                GatewayLogLevel.from(entry.level).priority >= selectedLevel.priority
            }
            .filter { entry in
                // Filter by category
                selectedCategory == "All" || entry.category == selectedCategory
            }
            .filter { entry in
                // Filter by search text
                guard !searchText.isEmpty else { return true }
                let text = searchText.lowercased()
                return (entry.message?.localizedCaseInsensitiveContains(text) ?? false) ||
                       (entry.category?.localizedCaseInsensitiveContains(text) ?? false)
            }
    }

    // MARK: - Lifecycle

    func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            // Initial fetch
            await self.fetchLogs()
            // Poll loop
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self.fetchLogs()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func clearLogs() {
        entries.removeAll()
        latestTimestampMs = nil
    }

    func exportLogs() -> String {
        filteredEntries.map { entry in
            let ts = entry.timestamp ?? "—"
            let lvl = (entry.level ?? "—").uppercased()
            let cat = entry.category ?? "—"
            let msg = entry.message ?? ""
            return "[\(ts)] [\(lvl)] [\(cat)] \(msg)"
        }.joined(separator: "\n")
    }

    // MARK: - Private

    private func fetchLogs() async {
        guard let client else { return }

        do {
            let result = try await client.logsTail(
                limit: latestTimestampMs == nil ? 200 : 100,
                level: nil,  // fetch all, filter client-side
                since: latestTimestampMs
            )

            let newEntries = result.entries
            guard !newEntries.isEmpty else { return }

            // Update latest timestamp for incremental fetching
            if let lastTs = newEntries.last?.timestamp {
                latestTimestampMs = parseTimestampToMs(lastTs)
            }

            // Merge new entries (avoid duplicates by id)
            let existingIds = Set(entries.map { $0.id })
            let uniqueNew = newEntries.filter { !existingIds.contains($0.id) }
            entries.append(contentsOf: uniqueNew)

            // Trim if over max
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }

            errorMessage = nil
        } catch is CancellationError {
            // Polling cancelled — normal
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.warning("Gateway logs fetch failed: \(error.localizedDescription)", category: "GatewayLogs")
        }
    }

    /// Parse an ISO 8601 or epoch-based timestamp string into epoch milliseconds.
    private func parseTimestampToMs(_ ts: String) -> Double? {
        // Try epoch ms (numeric string)
        if let ms = Double(ts) {
            return ms
        }
        // Try ISO 8601
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: ts) {
            return date.timeIntervalSince1970 * 1000
        }
        // Retry without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: ts) {
            return date.timeIntervalSince1970 * 1000
        }
        return nil
    }
}
