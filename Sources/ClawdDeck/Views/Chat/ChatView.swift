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
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if viewModel.isStreaming {
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
                onSend: {
                    Task { await viewModel.sendMessage() }
                },
                onAbort: {
                    Task { await viewModel.abortGeneration() }
                }
            )
        }
        .navigationTitle(viewModel.session?.displayTitle ?? "Chat")
        .task {
            if viewModel.messages.isEmpty {
                await viewModel.loadHistory()
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if viewModel.isStreaming {
                proxy.scrollTo("typing-indicator", anchor: .bottom)
            } else if let lastId = viewModel.messages.last?.id {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}
