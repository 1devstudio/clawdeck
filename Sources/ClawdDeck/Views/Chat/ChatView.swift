import SwiftUI
import MarkdownUI

/// Center column: message list with composer at the bottom.
struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        VStack(spacing: 0) {
            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                agentDisplayName: viewModel.agentDisplayName
                            )
                            .id(message.id)
                        }

                        if viewModel.isStreaming && viewModel.messages.last?.state != .streaming {
                            // Show typing indicator while waiting for first delta
                            TypingIndicator()
                                .id("typing-indicator")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onAppear { scrollProxy = proxy }
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.isStreaming) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.streamingContentVersion) { _, _ in
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }

            Divider()

            // Error banner
            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.clearError()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.yellow.opacity(0.1))
            }

            // Composer
            MessageComposer(
                text: $viewModel.draftText,
                isSending: viewModel.isSending,
                isStreaming: viewModel.isStreaming,
                pendingAttachments: viewModel.pendingAttachments,
                onSend: {
                    Task { await viewModel.sendMessage() }
                },
                onAbort: {
                    Task { await viewModel.abortGeneration() }
                },
                onAddAttachment: { url in
                    viewModel.addAttachment(from: url)
                },
                onPasteImage: { image in
                    viewModel.addAttachment(image: image)
                },
                onRemoveAttachment: { attachment in
                    viewModel.removeAttachment(attachment)
                }
            )
        }
        // Title is set at the MainView level (agent name)
        .task {
            if viewModel.messages.isEmpty {
                await viewModel.loadHistory()
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let scroll = {
            if let lastId = viewModel.messages.last?.id {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { scroll() }
        } else {
            scroll()
        }
    }
}
