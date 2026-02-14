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
                        // "Load earlier messages" button
                        if viewModel.hasMoreMessages {
                            Button {
                                // Remember the topmost visible message so we can
                                // scroll back to it after more messages appear.
                                let anchorId = viewModel.messages.first?.id
                                viewModel.loadMoreMessages()
                                if let anchorId {
                                    // Scroll to keep the user's position stable
                                    DispatchQueue.main.async {
                                        proxy.scrollTo(anchorId, anchor: .top)
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.circle")
                                    Text("Load earlier messages")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .id("load-more-button")
                        }

                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                agentDisplayName: viewModel.agentDisplayName,
                                searchQuery: viewModel.searchQuery,
                                isCurrentMatch: message.id == viewModel.focusedMatchId
                            )
                            .id(message.id)
                        }

                        if viewModel.isStreaming && viewModel.messages.last?.state != .streaming {
                            // Show typing indicator while waiting for first delta
                            TypingIndicator()
                                .id("typing-indicator")
                        }

                        // Invisible anchor at the very bottom — always rendered
                        // even when LazyVStack hasn't materialised the last
                        // message yet, so scrollTo has a reliable target.
                        Color.clear
                            .frame(height: 1)
                            .id("bottom-anchor")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollContentBackground(.hidden)
                .background {
                    ChatPatternBackground()
                }
                .onAppear {
                    scrollProxy = proxy
                    // Scroll to bottom when the view first appears (session switch).
                    // Dispatch async so the LazyVStack has laid out the bottom anchor.
                    DispatchQueue.main.async {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.isStreaming) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.streamingContentVersion) { _, _ in
                    scrollToBottom(proxy: proxy, animated: false)
                }
                .onChange(of: viewModel.focusedMatchId) { _, matchId in
                    if let matchId {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(matchId, anchor: .center)
                        }
                    }
                }
            }

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
        // History is loaded by AppViewModel.selectSession() — no .task needed here.
        // Adding a .task would race with selectSession and cancel the in-flight load.
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let scroll = {
            proxy.scrollTo("bottom-anchor", anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { scroll() }
        } else {
            scroll()
        }
    }
}
