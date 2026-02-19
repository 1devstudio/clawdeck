import Foundation
import SwiftUI

/// ViewModel for the cron jobs viewer.
@Observable
@MainActor
final class CronViewModel {

    // MARK: - Dependencies

    private weak var appViewModel: AppViewModel?

    // MARK: - State

    var jobs: [CronJobSummary] = []
    var isLoading = false
    var errorMessage: String?

    /// Job ID currently expanded to show run history.
    var expandedJobId: String?

    /// Cached run history per job ID.
    var runHistory: [String: [CronRunEntry]] = [:]

    /// Job IDs currently performing an action (run/toggle/delete).
    var busyJobIds: Set<String> = []

    // MARK: - Grouped jobs

    struct JobGroup: Identifiable {
        let title: String
        let icon: String
        let jobs: [CronJobSummary]
        var id: String { title }
    }

    var groupedJobs: [JobGroup] {
        let recurring = jobs.filter { $0.enabled && !($0.deleteAfterRun ?? false) }
            .sorted { ($0.state?.nextRunAtMs ?? 0) < ($1.state?.nextRunAtMs ?? 0) }
        let oneShot = jobs.filter { $0.enabled && ($0.deleteAfterRun ?? false) }
            .sorted { ($0.state?.nextRunAtMs ?? 0) < ($1.state?.nextRunAtMs ?? 0) }
        let disabled = jobs.filter { !$0.enabled }
            .sorted { $0.name < $1.name }

        var groups: [JobGroup] = []
        if !recurring.isEmpty { groups.append(JobGroup(title: "Recurring", icon: "arrow.trianglehead.2.counterclockwise.rotate.90", jobs: recurring)) }
        if !oneShot.isEmpty { groups.append(JobGroup(title: "One-shot", icon: "1.circle", jobs: oneShot)) }
        if !disabled.isEmpty { groups.append(JobGroup(title: "Disabled", icon: "pause.circle", jobs: disabled)) }
        return groups
    }

    // MARK: - Init

    init(appViewModel: AppViewModel?) {
        self.appViewModel = appViewModel
    }

    // MARK: - Data loading

    func loadJobs() async {
        guard let client = appViewModel?.activeClient else {
            errorMessage = "No active gateway connection"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await client.cronList()
            jobs = result.jobs
        } catch {
            errorMessage = "Failed to load cron jobs: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func loadRunHistory(for jobId: String) async {
        guard let client = appViewModel?.activeClient else { return }

        do {
            let result = try await client.cronRuns(jobId: jobId, limit: 5)
            runHistory[jobId] = result.entries
        } catch {
            AppLogger.error("Failed to load cron runs for \(jobId): \(error)", category: "Cron")
        }
    }

    // MARK: - Actions

    func toggleEnabled(_ job: CronJobSummary) async {
        guard let client = appViewModel?.activeClient else { return }
        busyJobIds.insert(job.id)
        defer { busyJobIds.remove(job.id) }

        do {
            try await client.cronUpdate(jobId: job.id, enabled: !job.enabled)
            await loadJobs()
        } catch {
            AppLogger.error("Failed to toggle cron job \(job.id): \(error)", category: "Cron")
        }
    }

    func runNow(_ job: CronJobSummary) async {
        guard let client = appViewModel?.activeClient else { return }
        busyJobIds.insert(job.id)
        defer { busyJobIds.remove(job.id) }

        do {
            try await client.cronRun(jobId: job.id)
            // Brief delay then refresh to pick up the new run state
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await loadJobs()
            await loadRunHistory(for: job.id)
        } catch {
            AppLogger.error("Failed to run cron job \(job.id): \(error)", category: "Cron")
        }
    }

    func removeJob(_ job: CronJobSummary) async {
        guard let client = appViewModel?.activeClient else { return }
        busyJobIds.insert(job.id)
        defer { busyJobIds.remove(job.id) }

        do {
            try await client.cronRemove(jobId: job.id)
            jobs.removeAll { $0.id == job.id }
            runHistory.removeValue(forKey: job.id)
        } catch {
            AppLogger.error("Failed to remove cron job \(job.id): \(error)", category: "Cron")
        }
    }

    // MARK: - Expand/collapse

    func toggleExpanded(_ jobId: String) {
        if expandedJobId == jobId {
            expandedJobId = nil
        } else {
            expandedJobId = jobId
            if runHistory[jobId] == nil {
                Task { await loadRunHistory(for: jobId) }
            }
        }
    }

    // MARK: - Formatting helpers

    static func formatSchedule(_ schedule: CronSchedule) -> String {
        switch schedule.kind {
        case "cron":
            guard let expr = schedule.expr else { return "cron" }
            let tz = schedule.tz.map { " (\($0))" } ?? ""
            let human = humanizeCron(expr)
            return "\(human)\(tz)"
        case "at":
            guard let expr = schedule.expr else { return "one-shot" }
            if let ms = Double(expr) {
                let date = Date(timeIntervalSince1970: ms / 1000)
                return "at \(Self.dateFormatter.string(from: date))"
            }
            return "at \(expr)"
        case "every":
            if let ms = schedule.intervalMs {
                return "every \(formatDuration(ms))"
            }
            return "repeating"
        default:
            return schedule.kind
        }
    }

    static func formatRelativeDate(_ epochMs: Double?) -> String? {
        guard let ms = epochMs else { return nil }
        let date = Date(timeIntervalSince1970: ms / 1000)
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func formatDuration(_ ms: Double) -> String {
        let seconds = ms / 1000
        if seconds < 60 { return String(format: "%.0fs", seconds) }
        let minutes = seconds / 60
        if minutes < 60 { return String(format: "%.0fm %.0fs", minutes, seconds.truncatingRemainder(dividingBy: 60)) }
        let hours = minutes / 60
        return String(format: "%.0fh %.0fm", hours, minutes.truncatingRemainder(dividingBy: 60))
    }

    static func statusIcon(_ status: String?) -> (name: String, color: Color) {
        switch status {
        case "ok": return ("checkmark.circle.fill", .green)
        case "error": return ("xmark.circle.fill", .red)
        default: return ("circle", .secondary)
        }
    }

    // MARK: - Private

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// Convert a 5-field cron expression to a human-readable string.
    private static func humanizeCron(_ expr: String) -> String {
        let parts = expr.split(separator: " ").map(String.init)
        guard parts.count == 5 else { return expr }

        let minute = parts[0]
        let hour = parts[1]
        let dayOfMonth = parts[2]
        let month = parts[3]
        let dayOfWeek = parts[4]

        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        // Build time string
        var time = ""
        if let h = Int(hour), let m = Int(minute) {
            time = String(format: "%d:%02d", h, m)
        } else {
            time = "\(hour):\(minute)"
        }

        // Simple cases
        if dayOfMonth == "*" && month == "*" {
            if dayOfWeek == "*" {
                return "Daily at \(time)"
            }
            let days = dayOfWeek.split(separator: ",").compactMap { part -> String? in
                if let i = Int(part), i >= 0, i < 7 { return dayNames[i] }
                // Handle named days
                let named = ["SUN": 0, "MON": 1, "TUE": 2, "WED": 3, "THU": 4, "FRI": 5, "SAT": 6]
                if let i = named[part.uppercased()] { return dayNames[i] }
                return String(part)
            }
            if days.count == 1 {
                return "\(days[0]) at \(time)"
            }
            return "\(days.joined(separator: ", ")) at \(time)"
        }

        return "\(expr)"
    }
}
