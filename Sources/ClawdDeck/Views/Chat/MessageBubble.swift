import SwiftUI
import MarkdownUI
import HighlightSwift

/// Renders a single chat message with role-appropriate styling.
struct MessageBubble: View {
    let message: ChatMessage
    var agentDisplayName: String = "Assistant"

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
                    .background(bubbleBackground)
                    .cornerRadius(12)
                    .overlay {
                        if message.state == .error {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        }
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

    private var bubbleBackground: some ShapeStyle {
        switch message.role {
        case .user:
            return AnyShapeStyle(Color.accentColor.opacity(0.12))
        case .assistant:
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
        case .system:
            return AnyShapeStyle(Color.yellow.opacity(0.08))
        case .toolCall, .toolResult:
            return AnyShapeStyle(Color.gray.opacity(0.08))
        }
    }
}
