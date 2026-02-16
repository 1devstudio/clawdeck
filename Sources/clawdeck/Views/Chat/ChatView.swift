import SwiftUI
import MarkdownUI

/// Center column: message list with composer at the bottom.
struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var scrollProxy: ScrollViewProxy?
    /// Throttle streaming scroll — don't fire on every single delta.
    @State private var lastStreamingScroll: Date = .distantPast

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
                                agentAvatarEmoji: viewModel.agentAvatarEmoji,
                                searchQuery: viewModel.searchQuery,
                                isCurrentMatch: message.id == viewModel.focusedMatchId
                            )
                            .id(message.id)
                        }

                        if viewModel.showTypingIndicator {
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
                .defaultScrollAnchor(.bottom)
                .onAppear {
                    scrollProxy = proxy
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    // A new message arrived — if it's from the assistant, we're no longer awaiting
                    if viewModel.isAwaitingResponse,
                       let last = viewModel.messages.last,
                       last.role == .assistant {
                        viewModel.isAwaitingResponse = false
                    }
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.isSending) { _, isSending in
                    if isSending { scrollToBottom(proxy: proxy) }
                }
                .onChange(of: viewModel.isStreaming) { _, isStreaming in
                    if isStreaming { viewModel.isAwaitingResponse = false }
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.streamingContentVersion) { _, _ in
                    // Throttle: scroll at most every 150ms during streaming
                    // to avoid layout thrashing with Markdown height changes.
                    let now = Date()
                    guard now.timeIntervalSince(lastStreamingScroll) > 0.15 else { return }
                    lastStreamingScroll = now
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

            // Model selector — above composer, right-aligned
            if !viewModel.availableModels.isEmpty {
                HStack {
                    Spacer()
                    ModelSelectorButton(
                        currentModel: viewModel.currentModelId,
                        defaultModel: viewModel.defaultModelId,
                        models: viewModel.availableModels,
                        onSelect: { modelId in
                            Task { await viewModel.selectModel(modelId) }
                        }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }

            // Composer
            MessageComposer(
                text: $viewModel.draftText,
                isSending: viewModel.isSending || viewModel.isAwaitingResponse,
                isStreaming: viewModel.isStreaming,
                pendingAttachments: viewModel.pendingAttachments,
                focusTrigger: viewModel.focusComposerTrigger,
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
        // Scroll to the last real message instead of a detached anchor.
        // LazyVStack may not have laid out cells near an invisible anchor,
        // causing the view to appear empty. Using the actual message id
        // forces the lazy stack to materialise that cell first.
        let targetId: String = {
            if viewModel.showTypingIndicator { return "typing-indicator" }
            if let last = viewModel.messages.last { return last.id }
            return "bottom-anchor"
        }()

        let scroll = {
            proxy.scrollTo(targetId, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { scroll() }
        } else {
            scroll()
        }
    }
}
