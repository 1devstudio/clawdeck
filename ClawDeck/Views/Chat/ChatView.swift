import SwiftUI
import MarkdownUI

private struct BottomScrollState: Equatable {
    var isAtBottom: Bool
    var contentHeight: CGFloat
}

/// Center column: message list with composer at the bottom.
struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var scrollProxy: ScrollViewProxy?
    /// Throttle streaming scroll — don't fire on every single delta.
    @State private var lastStreamingScroll: Date = .distantPast

    /// Whether the user is scrolled to (or near) the bottom of the chat.
    /// When true, new messages and streaming deltas auto-scroll to bottom.
    /// When false, the view stays put so the user can read history.
    @State private var isNearBottom: Bool = true

    /// Message whose steps are shown in the right sidebar (nil = sidebar hidden).
    /// Storing the message (which is @Observable) keeps the sidebar reactive during streaming.
    @State private var sidebarMessage: ChatMessage? = nil

    /// Threshold (in points) for considering the user "near the bottom".
    /// Accounts for overscroll bounce and minor offsets.
    private let nearBottomThreshold: CGFloat = 120

    var body: some View {
        HStack(spacing: 0) {
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
                                },
                                onRetry: (message.role == .user && message.state == .error) ? {
                                    Task { await viewModel.retryMessage(id: message.id) }
                                } : nil
                            )
                            .id(message.id)
                        }

                        if viewModel.showTypingIndicator {
                            TypingIndicator()
                                .id("typing-indicator")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .onScrollGeometryChange(for: BottomScrollState.self) { geometry in
                    // Calculate distance from bottom:
                    // contentSize - contentOffset - viewHeight = remaining scroll distance
                    let remaining = geometry.contentSize.height
                        - geometry.contentOffset.y
                        - geometry.containerSize.height
                    return BottomScrollState(isAtBottom: remaining <= nearBottomThreshold, contentHeight: geometry.contentSize.height)
                } action: { old, new in
                    if new.isAtBottom {
                        isNearBottom = true
                    } else if new.contentHeight <= old.contentHeight {
                        // Content didn't grow — user scrolled away
                        isNearBottom = false
                    }
                    // If content grew but user didn't scroll, keep isNearBottom as-is
                    // so auto-scroll continues working
                }
                .defaultScrollAnchor(.bottom)
                .safeAreaInset(edge: .top, spacing: 0) {
                    // Connection banner at top — non-dismissible
                    if !viewModel.isConnected {
                        ConnectionBanner(
                            state: viewModel.activeConnectionState,
                            onReconnect: {
                                Task { await viewModel.reconnect() }
                            }
                        )
                    }
                }
                // Floating "scroll to bottom" button — shown when user scrolls up
                .overlay(alignment: .bottomTrailing) {
                    if !isNearBottom {
                        Button {
                            scrollToBottom(proxy: proxy)
                        } label: {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(.thinMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .animation(.easeOut(duration: 0.15), value: isNearBottom)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // Bottom bar: error banner + model selector + composer
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
                            isDisabled: !viewModel.isConnected,
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
                    .background(.clear)
                }
                .overlay {
                    if viewModel.isLoadingHistory && viewModel.messages.isEmpty {
                        ContentUnavailableView {
                            Label {
                                Text("Loading Messages")
                            } icon: {
                                ProgressView()
                                    .controlSize(.large)
                            }
                        } description: {
                            Text("Fetching conversation history…")
                        }
                        .padding(32)
                        .background { ThemedSidebarBackground() }
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.isLoadingHistory)
                .onAppear {
                    scrollProxy = proxy
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if viewModel.isAwaitingResponse,
                       let last = viewModel.messages.last,
                       last.role == .assistant {
                        viewModel.isAwaitingResponse = false
                    }
                    // Defer by one run-loop tick so LazyVStack can finish laying
                    // out newly added views before we ask the proxy to scroll.
                    DispatchQueue.main.async {
                        scrollToBottomIfNeeded(proxy: proxy)
                    }
                }
                .onChange(of: viewModel.isSending) { _, isSending in
                    // Always scroll when the user sends a message
                    if isSending { scrollToBottom(proxy: proxy) }
                }
                .onChange(of: viewModel.isStreaming) { _, isStreaming in
                    if isStreaming { viewModel.isAwaitingResponse = false }
                    scrollToBottomIfNeeded(proxy: proxy)
                }
                .onChange(of: viewModel.streamingContentVersion) { _, _ in
                    guard isNearBottom else { return }
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
                .onChange(of: viewModel.sessionKey) { _, _ in
                    // Reset local state that was previously handled by .id() destruction.
                    // Don't call scrollToBottom here — .defaultScrollAnchor(.bottom) handles
                    // initial positioning, and an immediate scroll races with LazyVStack layout.
                    isNearBottom = true
                    sidebarMessage = nil
                    lastStreamingScroll = .distantPast
                }
            }

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

    /// Scroll to the bottom only when the user is near the bottom (or has just sent a message).
    private func scrollToBottomIfNeeded(proxy: ScrollViewProxy) {
        guard isNearBottom else { return }
        scrollToBottom(proxy: proxy)
    }

    /// Unconditionally scroll to the last message.
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
