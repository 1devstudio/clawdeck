import SwiftUI
import HighlightSwift

/// Sheet presenting cron jobs in a card-based layout.
struct CronJobsSheet: View {
    let appViewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CronViewModel
    @State private var selectedFilter: JobFilter = .recurring
    @State private var selectedJobId: String?

    enum JobFilter: String, CaseIterable {
        case recurring = "Recurring"
        case oneShot = "One-shot"
        case outdated = "Not Active"

        var icon: String {
            switch self {
            case .recurring: return "arrow.trianglehead.2.counterclockwise.rotate.90"
            case .oneShot: return "1.circle"
            case .outdated: return "clock.badge.xmark"
            }
        }
    }

    /// Whether a job is outdated — disabled or has no future run scheduled.
    private static func isOutdated(_ job: CronJobSummary) -> Bool {
        if !job.enabled { return true }
        guard let nextMs = job.state?.nextRunAtMs else { return true }
        return Date(timeIntervalSince1970: nextMs / 1000) < Date()
    }

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
        self._viewModel = State(initialValue: CronViewModel(appViewModel: appViewModel))
    }

    /// The currently selected job (if viewing details).
    private var selectedJob: CronJobSummary? {
        guard let id = selectedJobId else { return nil }
        return viewModel.jobs.first { $0.id == id }
    }

    /// Jobs matching the currently selected filter tab.
    private var filteredJobs: [CronJobSummary] {
        switch selectedFilter {
        case .recurring:
            return viewModel.jobs
                .filter { $0.enabled && !($0.deleteAfterRun ?? false) && !Self.isOutdated($0) }
                .sorted { ($0.state?.nextRunAtMs ?? 0) < ($1.state?.nextRunAtMs ?? 0) }
        case .oneShot:
            return viewModel.jobs
                .filter { $0.enabled && ($0.deleteAfterRun ?? false) && !Self.isOutdated($0) }
                .sorted { ($0.state?.nextRunAtMs ?? 0) < ($1.state?.nextRunAtMs ?? 0) }
        case .outdated:
            return viewModel.jobs
                .filter { Self.isOutdated($0) }
                .sorted { $0.name < $1.name }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let job = selectedJob {
                // Detail view — inline, same window
                CronJobDetailView(
                    job: job,
                    isBusy: viewModel.busyJobIds.contains(job.id),
                    runHistory: viewModel.runHistory[job.id],
                    onBack: { withAnimation(.easeInOut(duration: 0.15)) { selectedJobId = nil } },
                    onDismiss: { dismiss() },
                    onToggleEnabled: {
                        let wasEnabled = job.enabled
                        Task {
                            await viewModel.toggleEnabled(job)
                            selectedJobId = nil
                            selectedFilter = wasEnabled ? .outdated : .recurring
                        }
                    },
                    onRemove: {
                        Task {
                            await viewModel.removeJob(job)
                            selectedJobId = nil
                        }
                    },
                    onUpdatePrompt: { newMessage in
                        do {
                            try await viewModel.updatePrompt(job, message: newMessage)
                            return true
                        } catch {
                            return false
                        }
                    }
                )
            } else {
                // List view
                header
                Divider()
                filterBar
                Divider()
                listContent
            }
        }
        .frame(width: 700, height: 520)
        .overlay(alignment: .bottom) {
            if let feedback = viewModel.actionFeedback {
                HStack(spacing: 6) {
                    Image(systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(feedback.isError ? .red : .green)
                    Text(feedback.message)
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: feedback.message)
            }
        }
        .task {
            await viewModel.loadJobs()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Text("Cron Jobs")
                .font(.headline)
            Spacer()
            Button {
                Task { await viewModel.loadJobs() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            .disabled(viewModel.isLoading)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Filter tabs

    private var filterBar: some View {
        HStack(spacing: 2) {
            ForEach(JobFilter.allCases, id: \.self) { filter in
                let count = jobCount(for: filter)
                Button {
                    selectedFilter = filter
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: filter.icon)
                            .font(.system(size: 10))
                        Text(filter.rawValue)
                            .font(.system(size: 12, weight: .medium))
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(selectedFilter == filter ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
                                )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedFilter == filter ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                    .foregroundStyle(selectedFilter == filter ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - List content

    @ViewBuilder
    private var listContent: some View {
        if viewModel.isLoading && viewModel.jobs.isEmpty {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Loading cron jobs…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        } else if let error = viewModel.errorMessage, viewModel.jobs.isEmpty {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.loadJobs() }
            }
            .buttonStyle(.bordered)
            Spacer()
        } else if filteredJobs.isEmpty {
            Spacer()
            ContentUnavailableView(
                "No \(selectedFilter.rawValue) Jobs",
                systemImage: "clock.badge.questionmark",
                description: Text("No \(selectedFilter.rawValue.lowercased()) jobs found.")
            )
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredJobs) { job in
                        CronJobCard(
                            job: job,
                            isBusy: viewModel.busyJobIds.contains(job.id),
                            onSelect: {
                                Task { await viewModel.loadRunHistory(for: job.id) }
                                withAnimation(.easeInOut(duration: 0.15)) { selectedJobId = job.id }
                            },
                            onToggleEnabled: {
                                let wasEnabled = job.enabled
                                Task {
                                    await viewModel.toggleEnabled(job)
                                    selectedFilter = wasEnabled ? .outdated : .recurring
                                }
                            },
                            onRemove: { Task { await viewModel.removeJob(job) } }
                        )
                    }
                }
                .padding(20)
            }
        }
    }

    private func jobCount(for filter: JobFilter) -> Int {
        switch filter {
        case .recurring: return viewModel.jobs.filter { $0.enabled && !($0.deleteAfterRun ?? false) && !Self.isOutdated($0) }.count
        case .oneShot: return viewModel.jobs.filter { $0.enabled && ($0.deleteAfterRun ?? false) && !Self.isOutdated($0) }.count
        case .outdated: return viewModel.jobs.filter { Self.isOutdated($0) }.count
        }
    }
}

// MARK: - Job Card

/// A compact card for a single cron job. Clicking navigates to the detail view.
struct CronJobCard: View {
    let job: CronJobSummary
    let isBusy: Bool
    var onSelect: () -> Void
    var onToggleEnabled: () -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top section — title + schedule (clickable)
            Button {
                onSelect()
            } label: {
                topSection
                    .padding(16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.horizontal, 16)

            // Bottom section — last/next run + actions
            bottomSection
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Top section

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                statusDot
                Text(job.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(job.enabled ? .primary : .secondary)

                Text(job.id.prefix(12))
                    .font(.system(size: 10, weight: .medium).monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary.opacity(0.5))
                    )

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                if job.schedule.kind == "cron", let expr = job.schedule.expr {
                    Text(expr)
                        .font(.system(size: 11, weight: .semibold).monospaced())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                }

                Text(CronViewModel.formatSchedule(job.schedule))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusDot: some View {
        Group {
            if isBusy {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 10, height: 10)
            } else if !job.enabled {
                Circle()
                    .fill(.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
            } else {
                let status = CronViewModel.statusIcon(job.state?.lastStatus)
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Bottom section

    private var bottomSection: some View {
        HStack(alignment: .center, spacing: 12) {
            if let lastRun = CronViewModel.formatRelativeDate(job.state?.lastRunAtMs) {
                let statusInfo = CronViewModel.statusIcon(job.state?.lastStatus)
                HStack(spacing: 4) {
                    Text("Last:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Image(systemName: statusInfo.name)
                        .font(.system(size: 10))
                        .foregroundStyle(statusInfo.color)
                    Text(lastRun)
                        .font(.system(size: 11))
                        .foregroundStyle(statusInfo.color)
                }
            }

            if let nextRun = CronViewModel.formatRelativeDate(job.state?.nextRunAtMs) {
                HStack(spacing: 4) {
                    Text("Next:")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(nextRun)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                if job.enabled {
                    Button { onToggleEnabled() } label: {
                        Label("Disable", systemImage: "pause")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isBusy)
                } else {
                    Button { onToggleEnabled() } label: {
                        Label("Enable", systemImage: "play")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isBusy)
                }

                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy)
            }
        }
    }
}

// MARK: - Job Detail View

/// Inline detail view for a single cron job — prompt, metadata, run history.
struct CronJobDetailView: View {
    let job: CronJobSummary
    let isBusy: Bool
    let runHistory: [CronRunEntry]?
    var onBack: () -> Void
    var onDismiss: () -> Void
    var onToggleEnabled: () -> Void
    var onRemove: () -> Void
    var onUpdatePrompt: ((String) async -> Bool)?

    @State private var isEditingPrompt = false
    @State private var draftPrompt = ""
    @State private var isSavingPrompt = false
    @FocusState private var isPromptEditorFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack(alignment: .center) {
                Button { onBack() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                statusDot
                Text(job.name)
                    .font(.system(size: 14, weight: .bold))

                Spacer()

                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    scheduleSection

                    if let message = job.payload?.message ?? job.payload?.text {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Prompt")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)

                            if isEditingPrompt {
                                promptEditor(currentMessage: message)
                            } else {
                                WrappingCodeBlock(
                                    code: message,
                                    language: "bash",
                                    onEdit: onUpdatePrompt != nil ? {
                                        draftPrompt = message
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isEditingPrompt = true
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            isPromptEditorFocused = true
                                        }
                                    } : nil
                                )
                            }
                        }
                    }

                    metadataSection

                    if let entries = runHistory, !entries.isEmpty {
                        runHistorySection(entries)
                    }
                }
                .padding(20)
            }

            Divider()

            // Action buttons — always visible at bottom
            actionButtons
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        HStack(spacing: 10) {
            if job.schedule.kind == "cron", let expr = job.schedule.expr {
                Text(expr)
                    .font(.system(size: 12, weight: .semibold).monospaced())
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.accentColor.opacity(0.1))
                    )
            }

            Text(CronViewModel.formatSchedule(job.schedule))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            if let lastRun = CronViewModel.formatRelativeDate(job.state?.lastRunAtMs) {
                let statusInfo = CronViewModel.statusIcon(job.state?.lastStatus)
                metadataCell(label: "Last Run") {
                    HStack(spacing: 4) {
                        Image(systemName: statusInfo.name)
                            .font(.system(size: 11))
                            .foregroundStyle(statusInfo.color)
                        Text(lastRun)
                            .font(.system(size: 13))
                            .foregroundStyle(statusInfo.color)
                    }
                }
            }

            if let nextRun = CronViewModel.formatRelativeDate(job.state?.nextRunAtMs) {
                metadataCell(label: "Next Run") {
                    Text(nextRun)
                        .font(.system(size: 13))
                }
            }

            if let duration = job.state?.lastDurationMs {
                metadataCell(label: "Duration") {
                    Text(CronViewModel.formatDuration(duration))
                        .font(.system(size: 13))
                }
            }

            if let target = job.sessionTarget {
                metadataCell(label: "Session") {
                    Text(target)
                        .font(.system(size: 13))
                }
            }

            if let channel = job.payload?.channel {
                metadataCell(label: "Deliver") {
                    Text(channel)
                        .font(.system(size: 13))
                }
            }

            if let wakeMode = job.wakeMode {
                metadataCell(label: "Wake Mode") {
                    HStack(spacing: 4) {
                        if wakeMode == "next-heartbeat" {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                        Text(wakeMode)
                            .font(.system(size: 13))
                    }
                }
            }
        }
    }

    private func metadataCell<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
            content()
        }
    }

    // MARK: - Prompt editor

    @ViewBuilder
    private func promptEditor(currentMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $draftPrompt)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 80, maxHeight: 200)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(editorBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                )
                .focused($isPromptEditorFocused)

            HStack {
                Text("\(draftPrompt.count) chars")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Spacer()

                Button("Cancel") { cancelEdit() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .disabled(isSavingPrompt)

                Button {
                    Task { await savePrompt() }
                } label: {
                    if isSavingPrompt {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 14, height: 14)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.accentColor)
                .disabled(
                    isSavingPrompt
                    || draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || draftPrompt == currentMessage
                )
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }

    private func cancelEdit() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditingPrompt = false
        }
        draftPrompt = ""
        isPromptEditorFocused = false
    }

    private func savePrompt() async {
        isSavingPrompt = true
        defer { isSavingPrompt = false }

        if let onUpdatePrompt, await onUpdatePrompt(draftPrompt) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isEditingPrompt = false
            }
            draftPrompt = ""
        }
    }

    private var editorBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.09, blue: 0.10)
            : Color(red: 0.97, green: 0.97, blue: 0.98)
    }

    // MARK: - Run history

    private func runHistorySection(_ entries: [CronRunEntry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent Runs")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                ForEach(entries.prefix(10)) { entry in
                    CronRunEntryRow(entry: entry)
                }
            }
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if job.enabled {
                Button { onToggleEnabled() } label: {
                    Label("Disable", systemImage: "pause")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isBusy)
            } else {
                Button { onToggleEnabled() } label: {
                    Label("Enable", systemImage: "play")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isBusy)
            }

            Spacer()

            Button(role: .destructive) { onRemove() } label: {
                Label("Remove", systemImage: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isBusy)
        }
    }

    private var statusDot: some View {
        Group {
            if isBusy {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 10, height: 10)
            } else if !job.enabled {
                Circle()
                    .fill(.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
            } else {
                let status = CronViewModel.statusIcon(job.state?.lastStatus)
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Cron Run Row (expandable, like ToolCallBlock)

/// An expandable row for a single cron run entry, styled like tool call steps.
private struct CronRunEntryRow: View {
    let entry: CronRunEntry
    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    private var statusInfo: (name: String, color: Color) {
        CronViewModel.statusIcon(entry.status)
    }

    private var hasContent: Bool {
        entry.summary != nil || entry.error != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible, clickable to expand
            Button {
                guard hasContent else { return }
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    // Status icon
                    Image(systemName: statusInfo.name)
                        .font(.system(size: 11))
                        .foregroundStyle(statusInfo.color)
                        .frame(width: 16)

                    // Timestamp
                    if let runAt = CronViewModel.formatRelativeDate(entry.runAtMs) {
                        Text(runAt)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                    }

                    // Duration pill
                    if let duration = entry.durationMs {
                        Text(CronViewModel.formatDuration(duration))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.fill.tertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    // Inline summary preview (collapsed only)
                    if !isExpanded, let summary = entry.summary {
                        Text(summary)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else if !isExpanded, let error = entry.error {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer()

                    // Expand chevron
                    if hasContent {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Divider().opacity(0.5)

                VStack(alignment: .leading, spacing: 8) {
                    if let summary = entry.summary {
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let error = entry.error {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 6, height: 6)
                                Text("ERROR")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.red)
                            }
                            Text(error)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.red.opacity(0.85))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.red.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.red.opacity(0.15), lineWidth: 0.5)
                                )
                        }
                    }
                }
                .padding(10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(rowBorder, lineWidth: 0.5)
        )
    }

    private var rowBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.04)
            : Color.black.opacity(0.03)
    }

    private var rowBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }
}

// MARK: - Wrapping Code Block

/// Like HighlightedCodeBlock but wraps lines instead of horizontal scrolling.
private struct WrappingCodeBlock: View {
    let code: String
    let language: String?
    var onEdit: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.messageTextSize) private var messageTextSize
    @Environment(\.codeHighlightTheme) private var codeHighlightTheme
    @State private var highlightResult: AttributedString?
    @State private var isCopied = false

    private let highlight = Highlight()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.capitalized ?? "Code")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                if let onEdit {
                    Button {
                        onEdit()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                            Text("Edit")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    isCopied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        isCopied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied" : "Copy")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(headerBackground)

            Divider().opacity(0.5)

            Group {
                if let highlighted = highlightResult {
                    Text(highlighted)
                        .font(.system(size: messageTextSize - 1, design: .monospaced))
                } else {
                    Text(code)
                        .font(.system(size: messageTextSize - 1, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
            .padding(12)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 0.5)
        )
        .task(id: code + (language ?? "") + codeHighlightTheme.rawValue + "\(colorScheme)") {
            await performHighlight()
        }
    }

    private func performHighlight() async {
        do {
            let colors: HighlightColors = colorScheme == .dark
                ? .dark(codeHighlightTheme)
                : .light(codeHighlightTheme)
            let result: HighlightResult
            if let lang = language, !lang.isEmpty {
                result = try await highlight.request(code, mode: .languageAlias(lang), colors: colors)
            } else {
                result = try await highlight.request(code, mode: .automatic, colors: colors)
            }
            highlightResult = result.attributedText
        } catch {
            highlightResult = nil
        }
    }

    private var codeBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.09, blue: 0.10)
            : Color(red: 0.97, green: 0.97, blue: 0.98)
    }

    private var headerBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.13, blue: 0.15)
            : Color(red: 0.93, green: 0.93, blue: 0.95)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.1)
            : Color.black.opacity(0.1)
    }
}
