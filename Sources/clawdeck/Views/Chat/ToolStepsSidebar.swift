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

            // Steps list — scrollable, all expanded
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { _, step in
                        switch step {
                        case .thinking(_, let content):
                            ThinkingStepRow(content: content)
                        case .tool(let toolCall):
                            ToolStepRow(
                                toolCall: toolCall,
                                stepNumber: toolStepNumber(for: toolCall),
                                totalSteps: toolCalls.count
                            )
                        }
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 380)
        .background(.ultraThinMaterial)
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

    /// Get the 1-based tool step number for a given tool call.
    private func toolStepNumber(for toolCall: ToolCall) -> Int {
        (toolCalls.firstIndex(where: { $0.id == toolCall.id }) ?? 0) + 1
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

    @State private var isExpanded: Bool = false

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

// MARK: - Tool Step Row

/// A single tool step in the sidebar, shown expanded.
struct ToolStepRow: View {
    let toolCall: ToolCall
    let stepNumber: Int
    let totalSteps: Int

    @Environment(\.messageTextSize) private var messageTextSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Step header
            HStack(spacing: 8) {
                // Phase indicator
                phaseIndicator

                // Step number
                Text("#\(stepNumber)")
                    .font(.system(size: messageTextSize - 3, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)

                // Tool icon + name
                Image(systemName: toolCall.iconName)
                    .font(.system(size: messageTextSize - 3, weight: .medium))
                    .foregroundStyle(toolIconColor)
                    .frame(width: 14)

                Text(toolCall.name)
                    .font(.system(size: messageTextSize - 1, weight: .semibold, design: .monospaced))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            // Meta summary (file path, command, etc.)
            if let meta = toolCall.meta {
                Text(meta)
                    .font(.system(size: messageTextSize - 3, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }

            // Arguments
            if let args = toolCall.args, !args.isEmpty {
                Divider().opacity(0.3)
                argsSection(args)
                    .padding(8)
            }

            // Result
            if let result = toolCall.result, !result.isEmpty {
                Divider().opacity(0.3)
                resultSection(result)
                    .padding(8)
            }
        }
        .background(stepBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(stepBorderColor, lineWidth: 0.5)
        )
    }

    // MARK: - Phase indicator

    @ViewBuilder
    private var phaseIndicator: some View {
        switch toolCall.phase {
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: messageTextSize - 2))
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: messageTextSize - 2))
                .foregroundStyle(.red)
        }
    }

    private var toolIconColor: Color {
        switch toolCall.phase {
        case .running: return .blue
        case .completed: return .secondary
        case .error: return .red
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func argsSection(_ args: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("INPUT")
                .font(.system(size: messageTextSize - 4, weight: .bold))
                .foregroundStyle(.secondary)

            let formatted = formatArgs(args)
            Text(formatted)
                .font(.system(size: messageTextSize - 2, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.85))
                .textSelection(.enabled)
                .lineLimit(12)
        }
    }

    @ViewBuilder
    private func resultSection(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(toolCall.isError ? "ERROR" : "OUTPUT")
                .font(.system(size: messageTextSize - 4, weight: .bold))
                .foregroundStyle(toolCall.isError ? .red : .secondary)

            let truncated = result.count > 1000
                ? String(result.prefix(1000)) + "\n… (\(result.count) chars)"
                : result

            Text(truncated)
                .font(.system(size: messageTextSize - 2, design: .monospaced))
                .foregroundStyle(toolCall.isError ? .red.opacity(0.8) : .primary.opacity(0.85))
                .textSelection(.enabled)
                .lineLimit(20)
        }
    }

    // MARK: - Formatting

    private func formatArgs(_ args: [String: Any]) -> String {
        // For exec/bash, show just the command
        let name = toolCall.name.lowercased()
        if (name == "exec" || name == "bash"), let cmd = args["command"] as? String {
            return String(cmd.prefix(500))
        }
        if (name == "read" || name == "write" || name == "edit"),
           let path = args["path"] as? String ?? args["file_path"] as? String {
            return path
        }

        // Generic JSON
        if let data = try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys, .prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            return String(str.prefix(500))
        }
        return String(describing: args).prefix(500).description
    }

    // MARK: - Styling

    private var stepBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.03)
            : Color.black.opacity(0.02)
    }

    private var stepBorderColor: Color {
        switch toolCall.phase {
        case .error: return .red.opacity(0.3)
        default: return Color(nsColor: .separatorColor).opacity(0.3)
        }
    }
}
