import SwiftUI

/// A collapsible block showing a tool call with its name, arguments, and result.
struct ToolCallBlock: View {
    let toolCall: ToolCall
    @Environment(\.themeColor) private var themeColor
    @Environment(\.messageTextSize) private var messageTextSize
    @Environment(\.colorScheme) private var colorScheme

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible, clickable to expand
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    // Phase indicator
                    phaseIndicator

                    // Tool icon
                    Image(systemName: toolCall.iconName)
                        .font(.system(size: messageTextSize - 3, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    // Tool name
                    Text(toolCall.name)
                        .font(.system(size: messageTextSize - 2, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)

                    // Meta (short summary of args)
                    if let meta = toolCall.meta {
                        Text(meta)
                            .font(.system(size: messageTextSize - 3, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    // Expand chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: messageTextSize - 4, weight: .semibold))
                        .foregroundStyle(.quaternary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 8) {
                    // Arguments
                    if let args = toolCall.args, !args.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Input")
                                .font(.system(size: messageTextSize - 4, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            Text(formatArgs(args))
                                .font(.system(size: messageTextSize - 3, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(12)
                                .textSelection(.enabled)
                        }
                    }

                    // Result
                    if let result = toolCall.result, !result.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(toolCall.isError ? "Error" : "Output")
                                .font(.system(size: messageTextSize - 4, weight: .semibold))
                                .foregroundStyle(toolCall.isError ? .red : .secondary)
                                .textCase(.uppercase)

                            Text(truncateResult(result))
                                .font(.system(size: messageTextSize - 3, design: .monospaced))
                                .foregroundStyle(toolCall.isError ? .red.opacity(0.8) : .secondary)
                                .lineLimit(20)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .glassEffect(.regular.tint(blockTint), in: .rect(cornerRadius: 8))
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
                .font(.system(size: messageTextSize - 3))
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: messageTextSize - 3))
                .foregroundStyle(.red)
        }
    }

    // MARK: - Styling

    private var blockTint: Color {
        switch toolCall.phase {
        case .running: return themeColor.opacity(0.3)
        case .completed: return .gray.opacity(0.2)
        case .error: return .red.opacity(0.2)
        }
    }

    // MARK: - Formatting

    private func formatArgs(_ args: [String: Any]) -> String {
        // Try compact JSON first
        if let jsonData = try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys, .fragmentsAllowed]),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            // If it's short enough, show as-is
            if jsonStr.count <= 200 {
                return jsonStr
            }
            // Otherwise pretty-print
            if let prettyData = try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys, .prettyPrinted]),
               let prettyStr = String(data: prettyData, encoding: .utf8) {
                return String(prettyStr.prefix(500))
            }
            return String(jsonStr.prefix(500))
        }
        return String(describing: args).prefix(500).description
    }

    private func truncateResult(_ result: String) -> String {
        if result.count <= 1000 { return result }
        return String(result.prefix(1000)) + "\n… (\(result.count) chars total)"
    }
}

/// Displays a vertical list of tool calls for a message.
struct ToolCallsView: View {
    let toolCalls: [ToolCall]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(toolCalls) { toolCall in
                ToolCallBlock(toolCall: toolCall)
            }
        }
    }
}
