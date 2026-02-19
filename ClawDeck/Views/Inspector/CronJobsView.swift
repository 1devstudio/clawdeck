import SwiftUI

/// Cron jobs list view — displayed as a tab in the Inspector panel.
struct CronJobsView: View {
    @Bindable var viewModel: CronViewModel

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.jobs.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.jobs.isEmpty {
                errorView(error)
            } else if viewModel.jobs.isEmpty {
                emptyView
            } else {
                jobsList
            }
        }
        .task {
            await viewModel.loadJobs()
        }
    }

    // MARK: - Job list

    private var jobsList: some View {
        List {
            ForEach(viewModel.groupedJobs) { group in
                Section {
                    ForEach(group.jobs) { job in
                        CronJobRow(
                            job: job,
                            isExpanded: viewModel.expandedJobId == job.id,
                            isBusy: viewModel.busyJobIds.contains(job.id),
                            runHistory: viewModel.runHistory[job.id],
                            onToggleExpand: { viewModel.toggleExpanded(job.id) },
                            onToggleEnabled: { Task { await viewModel.toggleEnabled(job) } },
                            onRunNow: { Task { await viewModel.runNow(job) } },
                            onRemove: { Task { await viewModel.removeJob(job) } }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Label(group.title, systemImage: group.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.loadJobs()
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Loading cron jobs…")
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
                Task { await viewModel.loadJobs() }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No Cron Jobs",
            systemImage: "clock.badge.questionmark",
            description: Text("No scheduled jobs found on this gateway.")
        )
    }
}

// MARK: - Job Row

/// A single cron job row with expandable details.
struct CronJobRow: View {
    let job: CronJobSummary
    let isExpanded: Bool
    let isBusy: Bool
    let runHistory: [CronRunEntry]?
    var onToggleExpand: () -> Void
    var onToggleEnabled: () -> Void
    var onRunNow: () -> Void
    var onRemove: () -> Void

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
                Text(job.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(job.enabled ? .primary : .secondary)

                HStack(spacing: 6) {
                    // Schedule
                    Label(CronViewModel.formatSchedule(job.schedule), systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    // Last run
                    if let lastRun = CronViewModel.formatRelativeDate(job.state?.lastRunAtMs) {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        let statusInfo = CronViewModel.statusIcon(job.state?.lastStatus)
                        Label(lastRun, systemImage: statusInfo.name)
                            .font(.system(size: 10))
                            .foregroundStyle(statusInfo.color)
                    }
                }
            }

            Spacer()

            // Chevron
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var statusIndicator: some View {
        Group {
            if isBusy {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
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
        .frame(width: 16)
    }

    // MARK: - Expanded details

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.vertical, 4)

            // Info grid
            detailGrid

            // Payload preview
            if let message = job.payload?.message ?? job.payload?.text {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Prompt")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .truncationMode(.tail)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.quaternary.opacity(0.5))
                        )
                }
            }

            // Run history
            if let entries = runHistory, !entries.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recent Runs")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(entries) { entry in
                        CronRunRow(entry: entry)
                    }
                }
            }

            // Action buttons
            actionButtons
        }
        .padding(.leading, 24)
        .padding(.trailing, 4)
        .padding(.bottom, 4)
    }

    private var detailGrid: some View {
        Grid(alignment: .leading, verticalSpacing: 4) {
            if let nextRun = CronViewModel.formatRelativeDate(job.state?.nextRunAtMs) {
                GridRow {
                    Text("Next run")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 65, alignment: .leading)
                    Text(nextRun)
                        .font(.system(size: 11))
                }
            }

            if let duration = job.state?.lastDurationMs {
                GridRow {
                    Text("Duration")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 65, alignment: .leading)
                    Text(CronViewModel.formatDuration(duration))
                        .font(.system(size: 11))
                }
            }

            if let target = job.sessionTarget {
                GridRow {
                    Text("Session")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 65, alignment: .leading)
                    Text(target)
                        .font(.system(size: 11))
                }
            }

            if let channel = job.payload?.channel {
                GridRow {
                    Text("Deliver")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 65, alignment: .leading)
                    Text(channel)
                        .font(.system(size: 11))
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if job.enabled {
                Button {
                    onRunNow()
                } label: {
                    Label("Run Now", systemImage: "play.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy)

                Button {
                    onToggleEnabled()
                } label: {
                    Label("Disable", systemImage: "pause")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy)
            } else {
                Button {
                    onToggleEnabled()
                } label: {
                    Label("Enable", systemImage: "play")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isBusy)
            }

            Spacer()

            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove", systemImage: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isBusy)
        }
        .padding(.top, 4)
    }
}

// MARK: - Run History Row

/// A single run history entry.
struct CronRunRow: View {
    let entry: CronRunEntry

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                if entry.summary != nil || entry.error != nil {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    let statusInfo = CronViewModel.statusIcon(entry.status)
                    Image(systemName: statusInfo.name)
                        .font(.system(size: 9))
                        .foregroundStyle(statusInfo.color)

                    if let runAt = CronViewModel.formatRelativeDate(entry.runAtMs) {
                        Text(runAt)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    if let duration = entry.durationMs {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(CronViewModel.formatDuration(duration))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if entry.summary != nil || entry.error != nil {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if let summary = entry.summary {
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                        .truncationMode(.tail)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary.opacity(0.3))
                        )
                } else if let error = entry.error {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(4)
                        .padding(6)
                }
            }
        }
        .padding(.vertical, 1)
    }
}
