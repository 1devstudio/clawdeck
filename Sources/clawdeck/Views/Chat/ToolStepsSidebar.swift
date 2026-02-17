import SwiftUI

/// A step shown in the sidebar — either a tool call or a thinking block.
enum SidebarStep: Identifiable {
    case tool(ToolCall)
    case thinking(id: String, content: String)

    var id: String {
        switch self {
        case .tool(let tc): return tc.id
        case .thinking(let id, _): return id
        }
    }
}

/// Right sidebar showing all steps for a message (tool calls + thinking), already expanded.
struct ToolStepsSidebar: View {
    let steps: [SidebarStep]
    let onClose: () -> Void

    @Environment(\.messageTextSize) private var messageTextSize
    @Environment(\.themeColor) private var themeColor

    /// Convenience: just the tool calls from steps.
    private var toolCalls: [ToolCall] {
        steps.compactMap { if case .tool(let tc) = $0 { return tc } else { return nil } }
    }

    /// Convenience: thinking blocks from steps.
    private var thinkingBlocks: [(id: String, content: String)] {
        steps.compactMap { if case .thinking(let id, let c) = $0 { return (id, c) } else { return nil } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header
            Divider()

            // Steps list — scrollable
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { _, step in
                        switch step {
                        case .thinking(_, let content):
                            ThinkingStepRow(content: content)
                        case .tool(let toolCall):
                            ToolCallBlock(toolCall: toolCall)
                        }
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 380)
        .background {
            ThemedToolsPanelBackground()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            // Status dot
            overallStatusDot

            Text("Steps")
                .font(.system(size: messageTextSize, weight: .semibold))

            Text("(\(steps.count))")
                .font(.system(size: messageTextSize - 1))
                .foregroundStyle(.secondary)

            Spacer()

            // Summary badges
            HStack(spacing: 6) {
                if !thinkingBlocks.isEmpty {
                    StatusBadge(count: thinkingBlocks.count, color: .purple, icon: "brain")
                }

                let succeeded = toolCalls.filter { $0.phase == .completed }.count
                let failed = toolCalls.filter { $0.phase == .error }.count
                let running = toolCalls.filter { $0.phase == .running }.count

                if succeeded > 0 {
                    StatusBadge(count: succeeded, color: .green, icon: "checkmark")
                }
                if failed > 0 {
                    StatusBadge(count: failed, color: .red, icon: "xmark")
                }
                if running > 0 {
                    StatusBadge(count: running, color: .blue, icon: "ellipsis")
                }
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var overallStatusDot: some View {
        let hasRunning = toolCalls.contains { $0.phase == .running }
        let hasError = toolCalls.contains { $0.phase == .error }

        if hasRunning {
            PulsingDot(color: .blue)
        } else if hasError {
            Circle().fill(.red).frame(width: 8, height: 8)
        } else {
            Circle().fill(.green).frame(width: 8, height: 8)
        }
    }
}

// MARK: - Thinking Step Row

/// A thinking/reasoning block shown in the sidebar.
struct ThinkingStepRow: View {
    let content: String

    @Environment(\.messageTextSize) private var messageTextSize
    @Environment(\.themeColor) private var themeColor
    @Environment(\.colorScheme) private var colorScheme

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.system(size: messageTextSize - 2, weight: .medium))
                        .foregroundStyle(.purple.opacity(0.8))

                    Text("Thought process")
                        .font(.system(size: messageTextSize - 1, weight: .semibold))

                    Text("(\(formatCharCount(content.count)))")
                        .font(.system(size: messageTextSize - 3))
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: messageTextSize - 4, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().opacity(0.3)

                ScrollView {
                    Text(content)
                        .font(.system(size: messageTextSize - 1))
                        .italic()
                        .foregroundStyle(.secondary.opacity(0.8))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 400)
            }
        }
        .background(stepBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.2), lineWidth: 0.5)
        )
    }

    private var stepBackground: Color {
        colorScheme == .dark
            ? Color.purple.opacity(0.04)
            : Color.purple.opacity(0.03)
    }

    private func formatCharCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk chars", Double(count) / 1000)
        }
        return "\(count) chars"
    }
}

// MARK: - Status Badge

/// Small badge showing count with colored icon.
private struct StatusBadge: View {
    let count: Int
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

// ToolStepRow removed — sidebar now reuses ToolCallBlock for rich formatting.
