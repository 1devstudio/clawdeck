import SwiftUI
import AppKit
import MarkdownUI
import HighlightSwift

/// Renders a single chat message with role-appropriate styling.
struct MessageBubble: View {
    let message: ChatMessage
    var agentDisplayName: String = "Assistant"
    var agentAvatarEmoji: String? = nil
    var searchQuery: String = ""
    @Environment(\.themeColor) private var themeColor
    @Environment(\.messageTextSize) private var messageTextSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.codeHighlightTheme) private var codeHighlightTheme
    var isCurrentMatch: Bool = false

    /// Callback when the user taps the steps pill (tool calls + thinking).
    var onStepsTapped: (([SidebarStep]) -> Void)? = nil

    @State private var isHovered = false
    @State private var copiedText = false
    @State private var copiedMarkdown = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Role label + tool steps pill
                HStack(spacing: 4) {
                    if message.role == .assistant {
                        if let emoji = agentAvatarEmoji {
                            Text(emoji)
                                .font(.system(size: messageTextSize - 3))
                        } else {
                            Image(systemName: "sparkle")
                                .font(.system(size: messageTextSize - 3))
                                .foregroundStyle(themeColor)
                        }
                    }
                    Text(roleLabel)
                        .font(.system(size: messageTextSize - 2))
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)

                    if message.state == .streaming {
                        ProgressView()
                            .controlSize(.mini)
                    }

                    // Steps pill — shown for messages with tool calls or thinking
                    if message.role == .assistant {
                        let allSteps = message.sidebarSteps
                        if !allSteps.isEmpty {
                            Spacer()
                            ToolStepsPill(steps: allSteps) {
                                onStepsTapped?(allSteps)
                            }
                        }
                    }
                }

                // Image attachments (above message bubble)
                if !message.images.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.images) { img in
                            Image(nsImage: img.image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 240, maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                        }
                        if message.role != .user {
                            Spacer()
                        }
                    }
                }

                // Message content — interleaved segments or plain text
                if message.hasSegments && message.role == .assistant {
                    // Render consolidated segments: merge adjacent text segments
                    // into a single bubble so they don't appear as separate messages.
                    let segments = consolidatedSegments
                    let lastTextId = segments.last(where: {
                        if case .text = $0.kind { return true }
                        return false
                    })?.id

                    ForEach(segments, id: \.id) { group in
                        switch group.kind {
                        case .text(let text):
                            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                textBubble(content: text, showMeta: group.id == lastTextId)
                            }
                        case .toolGroup(let toolCalls):
                            ToolCallsView(toolCalls: toolCalls)
                                .padding(.leading, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .thinking(let content):
                            ThinkingBlockView(
                                content: content,
                                isStreaming: message.state == .streaming
                            )
                            .padding(.leading, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else if hasTextContent {
                    // Non-assistant or no segments — render as single bubble
                    textBubble(content: message.content)
                }

                // Error message
                if message.state == .error, let error = message.errorMessage {
                    Text(error)
                        .font(.system(size: messageTextSize - 3))
                        .foregroundStyle(.red)
                }

                // Sending indicator
                if message.state == .sending {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Sending…")
                            .font(.system(size: messageTextSize - 3))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }

            if message.role != .user {
                Spacer(minLength: 60)
            }
        }
    }

    // MARK: - Text bubble

    @ViewBuilder
    private func textBubble(content: String, showMeta: Bool = true) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if message.role == .assistant && message.state != .error {
                        Markdown(content)
                            .markdownTextStyle {
                                FontSize(messageTextSize)
                            }
                            .markdownTextStyle(\.code) {
                                FontFamilyVariant(.monospaced)
                                FontSize(.em(0.88))
                                ForegroundColor(inlineCodeColor)
                                BackgroundColor(inlineCodeColor.opacity(0.12))
                            }
                            .markdownBlockStyle(\.codeBlock) { configuration in
                                HighlightedCodeBlock(
                                    code: configuration.content,
                                    language: configuration.language
                                )
                                .markdownMargin(top: .em(0.4), bottom: .em(0.4))
                            }
                            .textSelection(.enabled)
                    } else {
                        Text(content)
                            .font(.system(size: messageTextSize))
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, showMeta ? 8 : 10)

                // Timestamp + usage inside the bubble
                if showMeta {
                    HStack(spacing: 6) {
                        Text(message.timestamp, style: .time)
                            .font(.system(size: messageTextSize - 3))
                            .foregroundStyle(.tertiary)

                        if message.role == .assistant, let usage = message.usage {
                            Spacer()
                            UsageBadgeView(usage: usage)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
            }
            .bubbleWidth(role: message.role)
            .glassEffect(bubbleGlassStyle, in: .rect(cornerRadius: 12))
            .overlay {
                if message.state == .error {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                } else if isCurrentMatch {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.yellow, lineWidth: 2)
                } else if isSearchMatch {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
                }
            }

            // Copy buttons — shown on hover for assistant messages
            if isHovered && message.role == .assistant && message.state != .streaming {
                MessageCopyButtons(
                    copiedText: $copiedText,
                    copiedMarkdown: $copiedMarkdown,
                    onCopyText: { copyRenderedText() },
                    onCopyMarkdown: { copyAsMarkdown() }
                )
                .padding(.top, 6)
                .padding(.trailing, 6)
            }
        }
    }

    // MARK: - Copy actions

    private func copyRenderedText() {
        let plainText = markdownToPlainText(message.content)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plainText, forType: .string)
        copiedText = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedText = false
        }
    }

    private func copyAsMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        copiedMarkdown = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedMarkdown = false
        }
    }

    /// Strip markdown syntax to produce clean plain text.
    private func markdownToPlainText(_ markdown: String) -> String {
        var text = markdown

        // Remove fenced code block markers (keep the code)
        text = text.replacingOccurrences(
            of: "```[a-zA-Z]*\\n",
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "```", with: "")

        // Remove heading markers
        text = text.replacingOccurrences(
            of: "(?m)^#{1,6}\\s+",
            with: "",
            options: .regularExpression
        )

        // Bold/italic
        text = text.replacingOccurrences(
            of: "\\*{1,3}(.+?)\\*{1,3}",
            with: "$1",
            options: .regularExpression
        )

        // Strikethrough
        text = text.replacingOccurrences(
            of: "~~(.+?)~~",
            with: "$1",
            options: .regularExpression
        )

        // Inline code
        text = text.replacingOccurrences(
            of: "`(.+?)`",
            with: "$1",
            options: .regularExpression
        )

        // Links: [text](url) → text
        text = text.replacingOccurrences(
            of: "\\[(.+?)\\]\\(.+?\\)",
            with: "$1",
            options: .regularExpression
        )

        // Block quotes
        text = text.replacingOccurrences(
            of: "(?m)^>\\s?",
            with: "",
            options: .regularExpression
        )

        // List markers
        text = text.replacingOccurrences(
            of: "(?m)^(\\s*)[-*+]\\s+",
            with: "$1",
            options: .regularExpression
        )

        // Horizontal rules
        text = text.replacingOccurrences(
            of: "(?m)^[-*_]{3,}$",
            with: "────────────",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether this message matches the search query.
    private var isSearchMatch: Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        return message.content.localizedCaseInsensitiveContains(query)
    }

    /// Whether the message has real text content (not just the image placeholder).
    private var hasTextContent: Bool {
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return false }
        if text == "📎 (image)" && !message.images.isEmpty { return false }
        return true
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return agentDisplayName
        case .system: return "System"
        case .toolCall: return "Tool Call"
        case .toolResult: return "Tool Result"
        }
    }

    private var inlineCodeColor: Color {
        codeHighlightTheme.keywordColor(for: colorScheme)
    }

    /// Liquid Glass style per message role.
    private var bubbleGlassStyle: Glass {
        switch message.role {
        case .user:
            return .regular
        case .assistant:
            return .regular
        case .system:
            return .regular.tint(.yellow)
        case .toolCall, .toolResult:
            return .regular.tint(.gray)
        }
    }

    // MARK: - Segment consolidation

    /// Merge text segments into as few bubbles as possible.
    ///
    /// For completed messages, all text segments are joined into a single bubble
    /// with tool groups collected separately. This prevents multi-step tool use
    /// turns from rendering 20+ tiny narration bubbles.
    ///
    /// For streaming messages, we keep the interleaved order so the user can
    /// see progress as it happens.
    private var consolidatedSegments: [ConsolidatedSegment] {
        if message.state == .streaming {
            return streamingConsolidatedSegments
        }
        return completedConsolidatedSegments
    }

    /// Streaming: collect all text into one bubble, keep thinking inline
    /// for live feedback, skip tool groups (shown via the pill + sidebar).
    private var streamingConsolidatedSegments: [ConsolidatedSegment] {
        var result: [ConsolidatedSegment] = []
        var allTexts: [String] = []
        var firstTextId: String?

        for segment in message.segments {
            switch segment {
            case .text(_, let content):
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if firstTextId == nil { firstTextId = segment.id }
                allTexts.append(content)

            case .toolGroup:
                // Shown in the pill + sidebar, not inline
                break

            case .thinking(let id, let content):
                result.append(ConsolidatedSegment(id: id, kind: .thinking(content)))
            }
        }

        if !allTexts.isEmpty, let id = firstTextId {
            let joined = allTexts.joined(separator: "\n\n")
            result.append(ConsolidatedSegment(id: id, kind: .text(joined)))
        }

        return result
    }

    /// Completed: collect all text into one bubble. Tool groups and thinking
    /// blocks are omitted (shown via the pill + sidebar).
    private var completedConsolidatedSegments: [ConsolidatedSegment] {
        var allTexts: [String] = []
        var firstTextId: String?

        for segment in message.segments {
            switch segment {
            case .text(_, let content):
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if firstTextId == nil { firstTextId = segment.id }
                allTexts.append(content)

            case .toolGroup:
                // Shown in the sidebar, not inline
                break

            case .thinking:
                // Shown in the sidebar, not inline
                break
            }
        }

        var result: [ConsolidatedSegment] = []
        if !allTexts.isEmpty, let id = firstTextId {
            let joined = allTexts.joined(separator: "\n\n")
            result.append(ConsolidatedSegment(id: id, kind: .text(joined)))
        }

        return result
    }
}

/// A consolidated rendering segment — adjacent text segments merged into one.
private struct ConsolidatedSegment: Identifiable {
    let id: String
    let kind: Kind

    enum Kind {
        case text(String)
        case toolGroup([ToolCall])
        case thinking(String)
    }
}

// MARK: - Usage Badge View

/// A subtle badge showing token usage and cost for an assistant message.
struct UsageBadgeView: View {
    let usage: MessageUsage
    @Environment(\.messageTextSize) private var messageTextSize
    @State private var showPopover = false

    var body: some View {
        if !usage.compactSummary.isEmpty {
            Button(action: { showPopover.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: messageTextSize - 5))
                    Text(usage.compactSummary)
                        .font(.system(size: messageTextSize - 4, design: .monospaced))
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                UsageDetailPopover(usage: usage)
            }
        }
    }
}

/// Detailed usage breakdown shown in a popover.
struct UsageDetailPopover: View {
    let usage: MessageUsage
    @Environment(\.messageTextSize) private var messageTextSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token Usage")
                .font(.system(size: messageTextSize - 1, weight: .semibold))
                .foregroundStyle(.primary)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                usageRow(label: "Input", tokens: usage.inputTokens, cost: usage.cost?.input)
                usageRow(label: "Output", tokens: usage.outputTokens, cost: usage.cost?.output)

                if usage.cacheReadTokens > 0 {
                    usageRow(label: "Cache Read", tokens: usage.cacheReadTokens, cost: usage.cost?.cacheRead)
                }
                if usage.cacheWriteTokens > 0 {
                    usageRow(label: "Cache Write", tokens: usage.cacheWriteTokens, cost: usage.cost?.cacheWrite)
                }

                Divider()
                    .gridCellColumns(3)

                GridRow {
                    Text("Total")
                        .fontWeight(.semibold)
                    Text(formatTokens(usage.totalTokens))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    if let total = usage.cost?.total, total > 0 {
                        Text(String(format: "$%.4f", total))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    } else {
                        Text("")
                    }
                }
            }
            .font(.system(size: messageTextSize - 2))
        }
        .padding(12)
        .frame(minWidth: 240)
    }

    @ViewBuilder
    private func usageRow(label: String, tokens: Int, cost: Double?) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(formatTokens(tokens))
                .monospacedDigit()
            if let cost, cost > 0 {
                Text(String(format: "$%.4f", cost))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("—")
                    .foregroundStyle(.quaternary)
            }
        }
    }

    private func formatTokens(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}

// MARK: - Thinking Block View

/// A collapsible block showing the model's thinking/reasoning process.
struct ThinkingBlockView: View {
    let content: String
    let isStreaming: Bool
    @Environment(\.messageTextSize) private var messageTextSize
    @Environment(\.themeColor) private var themeColor

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible, clickable to expand
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    if isStreaming {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "brain")
                            .font(.system(size: messageTextSize - 3, weight: .medium))
                            .foregroundStyle(themeColor.opacity(0.7))
                    }

                    Text(isStreaming ? "Thinking…" : "Thought process")
                        .font(.system(size: messageTextSize - 2, weight: .medium))
                        .foregroundStyle(.secondary)

                    if !isStreaming {
                        Text("(\(formatCharCount(content.count)))")
                            .font(.system(size: messageTextSize - 3))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

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
            if isExpanded || isStreaming {
                Divider()
                    .opacity(0.5)

                ScrollView {
                    Text(content)
                        .font(.system(size: messageTextSize - 1))
                        .italic()
                        .foregroundStyle(.secondary.opacity(0.8))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 300)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
        .onAppear {
            if isStreaming { isExpanded = true }
        }
    }

    private func formatCharCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk chars", Double(count) / 1000)
        }
        return "\(count) chars"
    }
}

// MARK: - Copy Buttons Overlay

/// Two small buttons for copying message content: plain text and markdown.
struct MessageCopyButtons: View {
    @Binding var copiedText: Bool
    @Binding var copiedMarkdown: Bool
    var onCopyText: () -> Void
    var onCopyMarkdown: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            // Copy as plain text
            Button(action: onCopyText) {
                Group {
                    if copiedText {
                        Image(systemName: "checkmark")
                    } else {
                        Image(systemName: "doc.on.doc")
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(copiedText ? .green : .secondary)
                .frame(width: 26, height: 22)
            }
            .buttonStyle(.plain)
            .help("Copy as plain text")

            // Copy as markdown
            Button(action: onCopyMarkdown) {
                Group {
                    if copiedMarkdown {
                        Image(systemName: "checkmark")
                    } else {
                        Text("MD")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                }
                .foregroundStyle(copiedMarkdown ? .green : .secondary)
                .frame(width: 26, height: 22)
            }
            .buttonStyle(.plain)
            .help("Copy as Markdown")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .glassEffect(in: .rect(cornerRadius: 6))
    }
}

// MARK: - Bubble Width

/// Environment key for the chat scroll view's available width.
private struct ChatWidthEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 600
}

extension EnvironmentValues {
    var chatWidth: CGFloat {
        get { self[ChatWidthEnvironmentKey.self] }
        set { self[ChatWidthEnvironmentKey.self] = newValue }
    }
}

/// Constrains a bubble to a max of 75% of the chat width,
/// with a minimum of 200pt.
private struct BubbleWidthModifier: ViewModifier {
    let role: MessageRole

    @Environment(\.chatWidth) private var chatWidth

    func body(content: Content) -> some View {
        content
            .frame(
                minWidth: 200,
                maxWidth: max(200, chatWidth * 0.75),
                alignment: .leading
            )
    }
}

extension View {
    func bubbleWidth(role: MessageRole) -> some View {
        modifier(BubbleWidthModifier(role: role))
    }
}
