import SwiftUI
import MarkdownUI

/// Center column: message list with composer at the bottom.
struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var scrollProxy: ScrollViewProxy?
    /// Throttle streaming scroll — don't fire on every single delta.
    @State private var lastStreamingScroll: Date = .distantPast

    /// Height of the bottom bar (model selector + composer) for scroll inset.
    @State private var bottomBarHeight: CGFloat = 60

    /// Message whose steps are shown in the right sidebar (nil = sidebar hidden).
    /// Storing the message (which is @Observable) keeps the sidebar reactive during streaming.
    @State private var sidebarMessage: ChatMessage? = nil

    var body: some View {
        HStack(spacing: 0) {
        ZStack(alignment: .bottom) {
            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // "Load earlier messages" button
                        if viewModel.hasMoreMessages {
                            Button {
                                let anchorId = viewModel.messages.first?.id
                                viewModel.loadMoreMessages()
                                if let anchorId {
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
                                isCurrentMatch: message.id == viewModel.focusedMatchId,
                                onStepsTapped: { _ in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if sidebarMessage != nil {
                                            sidebarMessage = nil
                                        } else {
                                            sidebarMessage = message
                                        }
                                    }
                                }
                            )
                            .id(message.id)
                        }

                        if viewModel.showTypingIndicator {
                            TypingIndicator()
                                .id("typing-indicator")
                        }

                        // Bottom spacer — ensures last message can scroll above the composer.
                        // This is real content height so LazyVStack accounts for it.
                        Spacer()
                            .frame(height: bottomBarHeight + 24)
                            .id("bottom-spacer")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .defaultScrollAnchor(.bottom)
                .onAppear {
                    scrollProxy = proxy
                }
                .onChange(of: viewModel.messages.count) { _, _ in
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

            // Loading overlay — shown while history is being fetched
            if viewModel.isLoadingHistory && viewModel.messages.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading messages…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial)
            }

            // Floating bottom bar: error banner + model selector + composer
            VStack(spacing: 0) {
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

                // Model selector + context usage — right-aligned
                if !viewModel.availableModels.isEmpty {
                    HStack(spacing: 8) {
                        Spacer()

                        if let total = viewModel.totalTokens, total > 0 {
                            ContextUsageView(
                                totalTokens: total,
                                contextTokens: viewModel.contextTokens
                            )
                        }

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
            .background(.ultraThinMaterial.opacity(0))
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: BottomBarHeightKey.self, value: geo.size.height)
                }
            )
            .onPreferenceChange(BottomBarHeightKey.self) { height in
                bottomBarHeight = height
            }
        } // end ZStack

        // Steps sidebar — slides in from the right, reactive to message changes
        if let msg = sidebarMessage {
            Divider()
            ToolStepsSidebar(steps: msg.sidebarSteps) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sidebarMessage = nil
                }
            }
            .transition(.move(edge: .trailing))
        }
        } // end HStack
    }

    /// Scroll to the last message, targeting it above the composer.
    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let targetId: String = {
            if viewModel.showTypingIndicator { return "typing-indicator" }
            if let last = viewModel.messages.last { return last.id }
            return ""
        }()
        guard !targetId.isEmpty else { return }

        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(targetId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(targetId, anchor: .bottom)
        }
    }
}

// MARK: - Layout preference keys

/// Preference key to measure the floating bottom bar height dynamically.
private struct BottomBarHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 60
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
