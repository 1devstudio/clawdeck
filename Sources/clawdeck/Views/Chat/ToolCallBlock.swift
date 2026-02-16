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
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    // Tool name
                    Text(toolCall.name)
                        .font(.system(size: messageTextSize - 2, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)

                    // Meta — inline code pill
                    if let meta = toolCall.meta {
                        InlineCodePill(text: meta, fontSize: messageTextSize - 3, color: themeColor)
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

                expandedContent
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }
        .glassEffect(.regular.tint(blockTint), in: .rect(cornerRadius: 8))
    }

    // MARK: - Expanded content

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            // Show command as a shell code block
            if let command = args["command"] as? String {
                ToolCodeBlock(
                    label: "Command",
                    code: command,
                    language: "bash",
                    fontSize: messageTextSize,
                    colorScheme: colorScheme
                )

                // Show other params (workdir, timeout, etc.) if present
                let otherArgs = args.filter { $0.key != "command" }
                if !otherArgs.isEmpty {
                    ToolParamsView(params: otherArgs, fontSize: messageTextSize)
                }
            } else {
                ToolCodeBlock(
                    label: "Input",
                    code: formatArgsJSON(args),
                    language: "json",
                    fontSize: messageTextSize,
                    colorScheme: colorScheme
                )
            }

        case "read":
            // Show file path prominently
            if let path = args["path"] as? String ?? args["file_path"] as? String {
                ToolCodeBlock(
                    label: "File",
                    code: path,
                    language: nil,
                    fontSize: messageTextSize,
                    colorScheme: colorScheme
                )
                let otherArgs = args.filter { $0.key != "path" && $0.key != "file_path" }
                if !otherArgs.isEmpty {
                    ToolParamsView(params: otherArgs, fontSize: messageTextSize)
                }
            }

        case "write":
            if let path = args["path"] as? String ?? args["file_path"] as? String {
                ToolCodeBlock(
                    label: "File",
                    code: path,
                    language: nil,
                    fontSize: messageTextSize,
                    colorScheme: colorScheme
                )
                // Show content being written (truncated)
                if let content = args["content"] as? String {
                    ToolCodeBlock(
                        label: "Content",
                        code: String(content.prefix(800)),
                        language: inferLanguage(from: path),
                        fontSize: messageTextSize,
                        colorScheme: colorScheme
                    )
                }
            }

        case "edit":
            if let path = args["path"] as? String ?? args["file_path"] as? String {
                ToolCodeBlock(
                    label: "File",
                    code: path,
                    language: nil,
                    fontSize: messageTextSize,
                    colorScheme: colorScheme
                )
                let lang = inferLanguage(from: path)
                if let oldText = args["oldText"] as? String ?? args["old_string"] as? String {
                    ToolCodeBlock(
                        label: "Find",
                        code: String(oldText.prefix(500)),
                        language: lang,
                        fontSize: messageTextSize,
                        colorScheme: colorScheme,
                        tint: .red.opacity(0.08)
                    )
                }
                if let newText = args["newText"] as? String ?? args["new_string"] as? String {
                    ToolCodeBlock(
                        label: "Replace",
                        code: String(newText.prefix(500)),
                        language: lang,
                        fontSize: messageTextSize,
                        colorScheme: colorScheme,
                        tint: .green.opacity(0.08)
                    )
                }
            }

        case "web_search":
            if let query = args["query"] as? String {
                ToolCodeBlock(
                    label: "Query",
                    code: query,
                    language: nil,
                    fontSize: messageTextSize,
                    colorScheme: colorScheme
                )
            }

        case "web_fetch":
            if let url = args["url"] as? String {
                ToolCodeBlock(
                    label: "URL",
                    code: url,
                    language: nil,
                    fontSize: messageTextSize,
                    colorScheme: colorScheme
                )
            }

        default:
            // Generic: show as formatted JSON
            ToolCodeBlock(
                label: "Input",
                code: formatArgsJSON(args),
                language: "json",
                fontSize: messageTextSize,
                colorScheme: colorScheme
            )
        }
    }

    @ViewBuilder
    private func expandedOutput(result: String) -> some View {
        let toolName = toolCall.name.lowercased()
        let isCodeOutput = ["exec", "bash", "read", "write", "edit"].contains(toolName)
        let truncated = truncateResult(result)

        ToolCodeBlock(
            label: toolCall.isError ? "Error" : "Output",
            code: truncated,
            language: isCodeOutput ? nil : nil,
            fontSize: messageTextSize,
            colorScheme: colorScheme,
            tint: toolCall.isError ? .red.opacity(0.08) : nil,
            isError: toolCall.isError
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

    private var blockTint: Color {
        switch toolCall.phase {
        case .running: return themeColor.opacity(0.3)
        case .completed: return .gray.opacity(0.2)
        case .error: return .red.opacity(0.2)
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

    /// Infer a syntax highlighting language from a file extension.
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

// MARK: - Inline Code Pill

/// A small inline code chip with monospace font and subtle background.
/// Used in the tool call header for file paths, commands, queries, etc.
struct InlineCodePill: View {
    let text: String
    let fontSize: Double
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Tool Code Block

/// A compact code block for displaying tool inputs/outputs.
/// Simpler than HighlightedCodeBlock — no syntax highlighting, just clean monospace.
struct ToolCodeBlock: View {
    let label: String
    let code: String
    let language: String?
    let fontSize: Double
    let colorScheme: ColorScheme
    var tint: Color? = nil
    var isError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Label header
            HStack {
                Text(label)
                    .font(.system(size: fontSize - 4, weight: .semibold))
                    .foregroundStyle(isError ? .red : .secondary)
                    .textCase(.uppercase)

                if let language {
                    Text(language)
                        .font(.system(size: fontSize - 5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Copy button
                CopyCodeButton(code: code, fontSize: fontSize)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(headerBackground)

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: fontSize - 2, design: .monospaced))
                    .foregroundStyle(isError ? .red.opacity(0.85) : .primary.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(maxHeight: 300)
        }
        .background(codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 0.5)
        )
    }

    private var codeBackground: Color {
        if let tint {
            return tint
        }
        return colorScheme == .dark
            ? Color(red: 0.06, green: 0.07, blue: 0.08)
            : Color(red: 0.96, green: 0.96, blue: 0.97)
    }

    private var headerBackground: Color {
        if let tint {
            return tint.opacity(1.5)  // Slightly stronger for header
        }
        return colorScheme == .dark
            ? Color(red: 0.10, green: 0.11, blue: 0.13)
            : Color(red: 0.92, green: 0.92, blue: 0.94)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
    }
}

// MARK: - Copy Code Button

/// Small copy button for code blocks inside tool calls.
struct CopyCodeButton: View {
    let code: String
    let fontSize: Double
    @State private var isCopied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            isCopied = true
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                isCopied = false
            }
        } label: {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: fontSize - 5, weight: .medium))
                .foregroundStyle(isCopied ? .green : .tertiary)
        }
        .buttonStyle(.plain)
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
                HStack(alignment: .top, spacing: 4) {
                    Text(key)
                        .font(.system(size: fontSize - 4, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    Text(formatValue(params[key]))
                        .font(.system(size: fontSize - 4, design: .monospaced))
                        .foregroundStyle(.secondary)
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
