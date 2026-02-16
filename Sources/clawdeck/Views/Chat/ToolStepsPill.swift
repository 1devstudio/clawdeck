import SwiftUI

/// Compact pill showing step summary (thinking + tool calls, status dot, count, duration).
/// Placed above the message bubble, right-aligned. Tapping opens the steps sidebar.
struct ToolStepsPill: View {
    let steps: [SidebarStep]
    let onTap: () -> Void

    @Environment(\.messageTextSize) private var messageTextSize

    /// Just the tool calls from steps.
    private var toolCalls: [ToolCall] {
        steps.compactMap { if case .tool(let tc) = $0 { return tc } else { return nil } }
    }

    /// Whether any thinking blocks are present.
    private var hasThinking: Bool {
        steps.contains { if case .thinking = $0 { return true } else { return false } }
    }

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
        .help("\(steps.count) steps — click to view details")
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
        let count = steps.count
        return count == 1 ? "1 step" : "\(count) steps"
    }

    /// Total duration from first tool start to last tool completion.
    private var totalDuration: String? {
        guard !toolCalls.isEmpty else { return nil }
        guard let earliest = toolCalls.map(\.startedAt).min() else { return nil }

        let end: Date
        if overallStatus == .running {
            end = Date()
        } else {
            guard let latest = toolCalls.map(\.startedAt).max() else { return nil }
            end = latest
        }

        let seconds = end.timeIntervalSince(earliest)
        if seconds < 0.1 { return nil }
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
