import SwiftUI
import MarkdownUI

/// Renders a single chat message with role-appropriate styling.
struct MessageBubble: View {
    let message: ChatMessage

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

                // Message content
                Group {
                    if message.role == .assistant && message.state != .error {
                        Markdown(message.content)
                            .markdownTextStyle {
                                FontSize(14)
                            }
                    } else {
                        Text(message.content)
                            .font(.body)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if message.state == .error {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
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

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return message.agentId ?? "Assistant"
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
