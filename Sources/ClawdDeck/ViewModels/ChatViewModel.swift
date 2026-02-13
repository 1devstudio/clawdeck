import Foundation
import SwiftUI

/// ViewModel for a single chat session view.
@Observable
@MainActor
final class ChatViewModel {
    // MARK: - Dependencies

    private let appViewModel: AppViewModel

    // MARK: - State

    /// The session key this view model is managing.
    let sessionKey: String

    /// Current draft message text.
    var draftText = ""

    /// Whether a message is currently being sent.
    var isSending = false

    /// Whether history is loading.
    var isLoadingHistory = false

    /// Error message to display.
    var errorMessage: String?

    /// Messages for this session.
    var messages: [ChatMessage] {
        appViewModel.messageStore.messages(for: sessionKey)
    }

    /// Whether the assistant is currently streaming a response.
    var isStreaming: Bool {
        appViewModel.messageStore.isStreaming(sessionKey: sessionKey)
    }

    /// The session object.
    var session: Session? {
        appViewModel.sessions.first { $0.key == sessionKey }
    }

    /// Tracks streaming content updates — observe to trigger auto-scroll.
    var streamingContentVersion: Int {
        appViewModel.messageStore.streamingContentVersion
    }

    // MARK: - Init

    init(sessionKey: String, appViewModel: AppViewModel) {
        self.sessionKey = sessionKey
        self.appViewModel = appViewModel
    }

    // MARK: - Actions

    /// Send the current draft message.
    func sendMessage() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        let outgoing = ChatMessage.outgoing(content: text, sessionKey: sessionKey)
        appViewModel.messageStore.addMessage(outgoing)
        draftText = ""
        isSending = true
        errorMessage = nil

        guard let client = appViewModel.connectionManager.activeClient else {
            appViewModel.messageStore.markError(
                messageId: outgoing.id,
                sessionKey: sessionKey,
                error: "Not connected"
            )
            isSending = false
            return
        }

        do {
            let _ = try await client.chatSend(sessionKey: sessionKey, message: text)
            appViewModel.messageStore.markSent(messageId: outgoing.id, sessionKey: sessionKey)
        } catch {
            appViewModel.messageStore.markError(
                messageId: outgoing.id,
                sessionKey: sessionKey,
                error: error.localizedDescription
            )
            errorMessage = error.localizedDescription
        }

        isSending = false
    }

    /// Abort the current generation.
    func abortGeneration() async {
        guard let client = appViewModel.connectionManager.activeClient else { return }
        do {
            try await client.chatAbort(sessionKey: sessionKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Load or reload chat history.
    func loadHistory() async {
        isLoadingHistory = true
        await appViewModel.loadHistory(for: sessionKey)
        isLoadingHistory = false
    }

    /// Clear the error message.
    func clearError() {
        errorMessage = nil
    }
}
