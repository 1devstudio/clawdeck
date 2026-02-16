import SwiftUI

/// Compact pill showing tool call summary (status dot, step count, duration).
/// Placed above the message bubble, right-aligned. Tapping opens the tool steps sidebar.
struct ToolStepsPill: View {
    let toolCalls: [ToolCall]
    let onTap: () -> Void

    @Environment(\.messageTextSize) private var messageTextSize

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // Status dot
                statusDot

                // Step count
                Text(stepsLabel)
                    .font(.system(size: messageTextSize - 3, weight: .medium))
                    .foregroundStyle(.secondary)

                // Duration (if available)
                if let duration = totalDuration {
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(duration)
                        .font(.system(size: messageTextSize - 3, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: messageTextSize - 5, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
            .overlay(
                Capsule()
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(toolCalls.count) tool steps — click to view details")
    }

    // MARK: - Status

    private var overallStatus: ToolCallPhase {
        let hasRunning = toolCalls.contains { $0.phase == .running }
        if hasRunning { return .running }
        let hasError = toolCalls.contains { $0.phase == .error }
        if hasError { return .error }
        return .completed
    }

    @ViewBuilder
    private var statusDot: some View {
        switch overallStatus {
        case .running:
            PulsingDot(color: .blue)
        case .completed:
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
        case .error:
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
        }
    }

    // MARK: - Labels

    private var stepsLabel: String {
        let count = toolCalls.count
        return count == 1 ? "1 step" : "\(count) steps"
    }

    /// Total duration from first tool start to last tool completion.
    private var totalDuration: String? {
        guard toolCalls.count > 0 else { return nil }
        guard let earliest = toolCalls.map(\.startedAt).min() else { return nil }

        // Use now for running, or the latest started + small buffer for completed
        let end: Date
        if overallStatus == .running {
            end = Date()
        } else {
            // Approximate end: last tool's startedAt + a small delta.
            // We don't track endedAt, so use the message timestamp gap.
            // For now, just show duration from first to last tool start.
            guard let latest = toolCalls.map(\.startedAt).max() else { return nil }
            end = latest
        }

        let seconds = end.timeIntervalSince(earliest)
        if seconds < 0.1 { return nil } // Too fast to be meaningful
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)m \(secs)s"
    }
}

// MARK: - Pulsing Dot

/// An animated pulsing dot for in-progress state.
struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}
