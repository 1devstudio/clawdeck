import SwiftUI
import AppKit

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
                        .foregroundStyle(toolIconColor)
                        .frame(width: 16)

                    // Tool name
                    Text(toolCall.name)
                        .font(.system(size: messageTextSize - 2, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)

                    // Meta — inline code pill
                    if let meta = toolCall.meta {
                        Text(meta)
                            .font(.system(size: messageTextSize - 3, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.fill.tertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Spacer()

                    // Expand chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: messageTextSize - 4, weight: .semibold))
                        .foregroundStyle(.tertiary)
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
                    .opacity(0.5)

                expandedContent
                    .padding(8)
            }
        }
        .themedToolBlock()
    }

    // MARK: - Expanded content

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Input section — smart formatting per tool type
            if let args = toolCall.args, !args.isEmpty {
                expandedInput(args: args)
            }

            // Output section
            if let result = toolCall.result, !result.isEmpty {
                expandedOutput(result: result)
            }
        }
    }

    @ViewBuilder
    private func expandedInput(args: [String: Any]) -> some View {
        let toolName = toolCall.name.lowercased()

        switch toolName {
        case "exec", "bash":
            if let command = args["command"] as? String {
                LabeledCodeBlock(label: "Command", code: command, language: "bash")

                let otherArgs = args.filter { $0.key != "command" }
                if !otherArgs.isEmpty {
                    ToolParamsView(params: otherArgs, fontSize: messageTextSize)
                }
            } else {
                LabeledCodeBlock(label: "Input", code: formatArgsJSON(args), language: "json")
            }

        case "read":
            if let path = args["path"] as? String ?? args["file_path"] as? String {
                LabeledCodeBlock(label: "File", code: path, language: nil)
                let otherArgs = args.filter { $0.key != "path" && $0.key != "file_path" }
                if !otherArgs.isEmpty {
                    ToolParamsView(params: otherArgs, fontSize: messageTextSize)
                }
            }

        case "write":
            if let path = args["path"] as? String ?? args["file_path"] as? String {
                LabeledCodeBlock(label: "File", code: path, language: nil)
                if let content = args["content"] as? String {
                    LabeledCodeBlock(
                        label: "Content",
                        code: String(content.prefix(800)),
                        language: inferLanguage(from: path)
                    )
                }
            }

        case "edit":
            if let path = args["path"] as? String ?? args["file_path"] as? String {
                LabeledCodeBlock(label: "File", code: path, language: nil)
                let lang = inferLanguage(from: path)
                if let oldText = args["oldText"] as? String ?? args["old_string"] as? String {
                    LabeledCodeBlock(
                        label: "Find",
                        code: String(oldText.prefix(500)),
                        language: lang,
                        tintColor: .red
                    )
                }
                if let newText = args["newText"] as? String ?? args["new_string"] as? String {
                    LabeledCodeBlock(
                        label: "Replace",
                        code: String(newText.prefix(500)),
                        language: lang,
                        tintColor: .green
                    )
                }
            }

        case "web_search":
            if let query = args["query"] as? String {
                LabeledCodeBlock(label: "Query", code: query, language: nil)
            }

        case "web_fetch":
            if let url = args["url"] as? String {
                LabeledCodeBlock(label: "URL", code: url, language: nil)
            }

        default:
            LabeledCodeBlock(label: "Input", code: formatArgsJSON(args), language: "json")
        }
    }

    @ViewBuilder
    private func expandedOutput(result: String) -> some View {
        let truncated = truncateResult(result)

        LabeledCodeBlock(
            label: toolCall.isError ? "Error" : "Output",
            code: truncated,
            language: nil,
            tintColor: toolCall.isError ? .red : nil
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
                .font(.system(size: messageTextSize - 3))
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: messageTextSize - 3))
                .foregroundStyle(.red)
        }
    }

    // MARK: - Styling

    private var toolIconColor: Color {
        switch toolCall.phase {
        case .running: return themeColor
        case .completed: return .secondary
        case .error: return .red
        }
    }

    // MARK: - Formatting helpers

    private func formatArgsJSON(_ args: [String: Any]) -> String {
        if let prettyData = try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys, .prettyPrinted]),
           let prettyStr = String(data: prettyData, encoding: .utf8) {
            return String(prettyStr.prefix(800))
        }
        if let jsonData = try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys]),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            return String(jsonStr.prefix(800))
        }
        return String(describing: args).prefix(800).description
    }

    private func truncateResult(_ result: String) -> String {
        if result.count <= 1500 { return result }
        return String(result.prefix(1500)) + "\n… (\(result.count) chars total)"
    }

    private func inferLanguage(from path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        let map: [String: String] = [
            "swift": "swift", "py": "python", "js": "javascript", "ts": "typescript",
            "tsx": "tsx", "jsx": "jsx", "rs": "rust", "go": "go", "rb": "ruby",
            "java": "java", "kt": "kotlin", "cs": "csharp", "cpp": "cpp", "c": "c",
            "h": "c", "m": "objectivec", "html": "html", "css": "css", "scss": "scss",
            "json": "json", "yaml": "yaml", "yml": "yaml", "toml": "toml",
            "xml": "xml", "sql": "sql", "sh": "bash", "bash": "bash", "zsh": "bash",
            "md": "markdown", "dockerfile": "dockerfile", "tf": "hcl",
        ]
        return map[ext]
    }
}

// MARK: - Labeled Code Block

/// A code block with a label header, using HighlightedCodeBlock for syntax highlighting.
/// Reuses the same theming as message code blocks for consistent appearance.
struct LabeledCodeBlock: View {
    let label: String
    let code: String
    let language: String?
    var tintColor: Color? = nil

    @Environment(\.messageTextSize) private var messageTextSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Label pill
            HStack(spacing: 4) {
                if let tint = tintColor {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                }
                Text(label.uppercased())
                    .font(.system(size: messageTextSize - 4, weight: .bold))
                    .foregroundStyle(tintColor ?? .secondary)
            }
            .padding(.bottom, 4)

            // Code block — reuse HighlightedCodeBlock for proper theming
            if isMultilineOrCode {
                HighlightedCodeBlock(
                    code: code,
                    language: language
                )
            } else {
                // Short single-line content — inline styled
                Text(code)
                    .font(.system(size: messageTextSize - 2, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(inlineBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(inlineBorder, lineWidth: 0.5)
                    )
            }
        }
    }

    /// Use HighlightedCodeBlock for multiline content or when a language is specified.
    private var isMultilineOrCode: Bool {
        language != nil || code.contains("\n") || code.count > 120
    }

    private var inlineBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.09, blue: 0.10)
            : Color(red: 0.97, green: 0.97, blue: 0.98)
    }

    private var inlineBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.1)
            : Color.black.opacity(0.1)
    }
}

// MARK: - Tool Params View

/// Shows additional tool parameters as key-value pairs (for non-primary args).
struct ToolParamsView: View {
    let params: [String: Any]
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(params.keys.sorted()), id: \.self) { key in
                HStack(alignment: .top, spacing: 6) {
                    Text(key)
                        .font(.system(size: fontSize - 3, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(formatValue(params[key]))
                        .font(.system(size: fontSize - 3, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.8))
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func formatValue(_ value: Any?) -> String {
        guard let value else { return "nil" }
        if let str = value as? String { return str }
        if let num = value as? Int { return String(num) }
        if let num = value as? Double { return String(num) }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        return String(describing: value)
    }
}

// MARK: - Tool Calls List

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
