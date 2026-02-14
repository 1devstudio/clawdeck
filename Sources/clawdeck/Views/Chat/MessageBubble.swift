import SwiftUI
import AppKit
import MarkdownUI
import HighlightSwift

/// Renders a single chat message with role-appropriate styling.
struct MessageBubble: View {
    let message: ChatMessage
    var agentDisplayName: String = "Assistant"
    var searchQuery: String = ""
    @Environment(\.themeColor) private var themeColor
    var isCurrentMatch: Bool = false

    @State private var isHovered = false
    @State private var copiedText = false
    @State private var copiedMarkdown = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Role label
                HStack(spacing: 4) {
                    if message.role == .assistant {
                        Image(systemName: "sparkle")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                    Text(roleLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)

                    if message.state == .streaming {
                        ProgressView()
                            .controlSize(.mini)
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

                // Message content (hidden for image-only messages)
                if hasTextContent {
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if message.role == .assistant && message.state != .error {
                                Markdown(message.content)
                                    .markdownTextStyle {
                                        FontSize(14)
                                    }
                                    .markdownTextStyle(\.code) {
                                        FontFamilyVariant(.monospaced)
                                        FontSize(.em(0.88))
                                        ForegroundColor(.purple)
                                        BackgroundColor(.purple.opacity(0.12))
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
                                Text(message.content)
                                    .font(.body)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
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
                    .onHover { hovering in
                        isHovered = hovering
                    }
                }

                // Error message
                if message.state == .error, let error = message.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                // Sending indicator
                if message.state == .sending {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Sending…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if message.role != .user {
                Spacer(minLength: 60)
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

    /// Liquid Glass style per message role.
    private var bubbleGlassStyle: some GlassEffectStyle {
        switch message.role {
        case .user:
            return .regular.tint(themeColor)
        case .assistant:
            return .regular
        case .system:
            return .regular.tint(.yellow)
        case .toolCall, .toolResult:
            return .regular.tint(.gray)
        }
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
