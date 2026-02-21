import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A pending image attachment in the composer, before sending.
struct PendingAttachment: Identifiable {
    let id = UUID()
    let image: NSImage
    let data: Data
    let mimeType: String
    let fileName: String?
}

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

    /// Search query bound from the top bar.
    var searchQuery = ""

    /// Index of the currently focused match within `searchMatchIds`.
    var currentMatchIndex: Int = 0

    /// Message IDs that match the current search query (in display order).
    var searchMatchIds: [String] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return messages
            .filter { $0.isVisible && $0.content.localizedCaseInsensitiveContains(query) }
            .map(\.id)
    }

    /// Navigate to the next search match.
    func nextMatch() {
        guard !searchMatchIds.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % searchMatchIds.count
    }

    /// Navigate to the previous search match.
    func previousMatch() {
        guard !searchMatchIds.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + searchMatchIds.count) % searchMatchIds.count
    }

    /// The message ID of the currently focused match (for scrolling).
    var focusedMatchId: String? {
        guard !searchMatchIds.isEmpty, currentMatchIndex < searchMatchIds.count else { return nil }
        return searchMatchIds[currentMatchIndex]
    }

    /// Pending image attachments to send with the next message.
    var pendingAttachments: [PendingAttachment] = []

    /// Whether a message is currently being sent (RPC in-flight).
    var isSending = false

    /// Whether we're waiting for the agent's first streaming delta after the RPC returned.
    /// Bridges the gap between `isSending` (RPC done) and `isStreaming` (first delta).
    var isAwaitingResponse = false

    /// Whether history is loading.
    var isLoadingHistory = false

    /// Error message to display.
    var errorMessage: String?

    /// Connection state of the active gateway.
    var activeConnectionState: ConnectionState {
        appViewModel.activeConnectionState
    }

    /// Whether the active gateway is connected and ready to send messages.
    var isConnected: Bool {
        activeConnectionState == .connected
    }

    /// Messages for this session.
    var messages: [ChatMessage] {
        appViewModel.messageStore.messages(for: sessionKey)
    }

    /// Whether the assistant is currently streaming a response.
    var isStreaming: Bool {
        appViewModel.messageStore.isStreaming(sessionKey: sessionKey)
    }

    /// Whether the typing indicator should be shown — covers the full lifecycle:
    /// sending (RPC in-flight) → awaiting response (RPC done, waiting for first delta) → streaming (before first content appears).
    var showTypingIndicator: Bool {
        isSending || isAwaitingResponse || (isStreaming && messages.last?.state != .streaming)
    }

    /// Whether there are older messages available to load.
    var hasMoreMessages: Bool {
        appViewModel.messageStore.hasMoreMessages(for: sessionKey)
    }

    /// Load the next page of older messages.
    func loadMoreMessages() {
        appViewModel.messageStore.loadMoreMessages(for: sessionKey)
    }

    /// The session object.
    var session: Session? {
        appViewModel.sessions.first { $0.key == sessionKey }
    }

    /// Tracks streaming content updates — observe to trigger auto-scroll.
    var streamingContentVersion: Int {
        appViewModel.messageStore.streamingContentVersion
    }

    /// Available models from the gateway (relayed from AppViewModel).
    var availableModels: [GatewayModel] {
        appViewModel.availableModels
    }

    /// The session's per-session model override as "provider/id" (nil = using agent default).
    var currentModelId: String? {
        guard let model = session?.model else { return nil }
        if let provider = session?.modelProvider {
            return "\(provider)/\(model)"
        }
        return model
    }

    /// The agent-level default model as "provider/id".
    var defaultModelId: String? {
        guard let model = appViewModel.defaultModelId else { return nil }
        if let provider = appViewModel.defaultModelProvider {
            return "\(provider)/\(model)"
        }
        return model
    }

    /// The session's total tokens used (context usage).
    var totalTokens: Int? {
        session?.totalTokens
    }

    /// The context window size for this session (from session or agent default).
    var contextTokens: Int? {
        session?.contextTokens ?? appViewModel.defaultContextTokens
    }

    /// Set a model override for this session. Pass `nil` to reset to default.
    func selectModel(_ modelId: String?) async {
        await appViewModel.setSessionModel(modelId, for: sessionKey)
    }

    /// Focus composer trigger — relays from AppViewModel.
    var focusComposerTrigger: Int {
        appViewModel.focusComposerTrigger
    }

    /// Display name of the active agent (from the connection profile).
    var agentDisplayName: String {
        appViewModel.activeBinding?.displayName(from: appViewModel.gatewayManager) ?? "Assistant"
    }

    /// Avatar emoji of the active agent from the gateway (e.g. "🤖"), or nil.
    var agentAvatarEmoji: String? {
        guard let binding = appViewModel.activeBinding,
              let summaries = appViewModel.gatewayManager.agentSummaries[binding.gatewayId],
              let summary = summaries.first(where: { $0.id == binding.agentId }) else { return nil }
        // Prefer emoji field, fall back to avatar
        if let emoji = summary.emoji, !emoji.isEmpty { return emoji }
        if let avatar = summary.avatar, !avatar.isEmpty { return avatar }
        return nil
    }

    // MARK: - Init

    init(sessionKey: String, appViewModel: AppViewModel) {
        self.sessionKey = sessionKey
        self.appViewModel = appViewModel
    }

    // MARK: - Actions

    /// Send the current draft message (with any pending attachments).
    func sendMessage() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !text.isEmpty || !attachments.isEmpty, !isSending else { return }

        // Build the message text — use a placeholder if only images
        let messageText = text.isEmpty ? "📎 (image)" : text

        let outgoing = ChatMessage.outgoing(content: messageText, sessionKey: sessionKey)
        // Attach images for display in the chat bubble
        outgoing.images = attachments.map { att in
            MessageImage(image: att.image, mimeType: att.mimeType, fileName: att.fileName)
        }

        appViewModel.messageStore.addMessage(outgoing)
        draftText = ""
        pendingAttachments = []
        isSending = true
        errorMessage = nil

        guard let client = appViewModel.activeClient else {
            appViewModel.messageStore.markError(
                messageId: outgoing.id,
                sessionKey: sessionKey,
                error: "Not connected"
            )
            isSending = false
            return
        }

        // Convert pending attachments to gateway format
        let chatAttachments: [ChatAttachment]? = attachments.isEmpty ? nil : attachments.map { att in
            ChatAttachment(
                content: att.data.base64EncodedString(),
                mimeType: att.mimeType,
                fileName: att.fileName,
                type: "image"
            )
        }

        do {
            let _ = try await client.chatSend(
                sessionKey: sessionKey,
                message: messageText,
                attachments: chatAttachments
            )
            appViewModel.messageStore.markSent(messageId: outgoing.id, sessionKey: sessionKey)
            // RPC succeeded — now wait for the agent's first streaming delta
            isAwaitingResponse = true
        } catch {
            let message = Self.userFriendlyError(error)
            appViewModel.messageStore.markError(
                messageId: outgoing.id,
                sessionKey: sessionKey,
                error: message
            )
            errorMessage = message
        }

        isSending = false
    }

    /// Retry sending a failed message.
    func retryMessage(id messageId: String) async {
        guard !isSending else { return }

        guard let message = messages.first(where: { $0.id == messageId }),
              message.state == .error,
              message.role == .user else {
            return
        }

        guard let client = appViewModel.activeClient else {
            appViewModel.messageStore.markError(
                messageId: messageId,
                sessionKey: sessionKey,
                error: "Not connected"
            )
            return
        }

        appViewModel.messageStore.markSending(messageId: messageId, sessionKey: sessionKey)
        isSending = true
        errorMessage = nil

        // Re-compress image attachments from stored NSImages
        let chatAttachments: [ChatAttachment]? = message.images.isEmpty ? nil : message.images.compactMap { img in
            guard let data = compressForUpload(image: img.image) else { return nil }
            return ChatAttachment(
                content: data.base64EncodedString(),
                mimeType: img.mimeType,
                fileName: img.fileName,
                type: "image"
            )
        }

        do {
            let _ = try await client.chatSend(
                sessionKey: sessionKey,
                message: message.content,
                attachments: chatAttachments
            )
            appViewModel.messageStore.markSent(messageId: messageId, sessionKey: sessionKey)
            isAwaitingResponse = true
        } catch {
            let friendlyError = Self.userFriendlyError(error)
            appViewModel.messageStore.markError(
                messageId: messageId,
                sessionKey: sessionKey,
                error: friendlyError
            )
            errorMessage = friendlyError
        }

        isSending = false
    }

    /// Abort the current generation.
    func abortGeneration() async {
        guard let client = appViewModel.activeClient else { return }
        do {
            try await client.chatAbort(sessionKey: sessionKey)
        } catch {
            errorMessage = error.localizedDescription
        }
        // Clear all active states so the indicator and abort button disappear immediately
        isSending = false
        isAwaitingResponse = false
        appViewModel.messageStore.finalizeStreaming(for: sessionKey)
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

    /// Manually trigger a reconnection to the active gateway.
    func reconnect() async {
        guard let binding = appViewModel.activeBinding else { return }
        await appViewModel.gatewayManager.reconnect(gatewayId: binding.gatewayId)
    }

    // MARK: - Attachments

    /// Maximum attachment size in bytes after encoding.
    /// Gateway WebSocket maxPayload is 512 KB, and base64 inflates by ~33%.
    /// So raw image data must be under ~380 KB to fit in the frame with JSON overhead.
    private static let maxAttachmentBytes = 350_000

    /// Maximum image dimension (width or height) — images are scaled down to fit.
    private static let maxImageDimension: CGFloat = 1200

    /// Add an image from a file URL.
    func addAttachment(from url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            errorMessage = "Could not load image from file"
            return
        }
        guard let data = compressForUpload(image: image) else {
            errorMessage = "Could not compress image for upload"
            return
        }
        let attachment = PendingAttachment(
            image: image,
            data: data,
            mimeType: "image/jpeg",
            fileName: url.lastPathComponent
        )
        pendingAttachments.append(attachment)
    }

    /// Add an image from NSImage (e.g. pasted from clipboard).
    func addAttachment(image: NSImage, fileName: String? = nil) {
        guard let data = compressForUpload(image: image) else {
            errorMessage = "Could not compress image for upload"
            return
        }
        let attachment = PendingAttachment(
            image: image,
            data: data,
            mimeType: "image/jpeg",
            fileName: fileName ?? "pasted-image.jpg"
        )
        pendingAttachments.append(attachment)
    }

    /// Remove a pending attachment.
    func removeAttachment(_ attachment: PendingAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    /// Compress and resize an image to fit within the gateway WebSocket payload limit.
    ///
    /// Strategy:
    /// 1. Scale down if larger than maxImageDimension
    /// 2. Encode as JPEG, starting at quality 0.8
    /// 3. If still too large, reduce quality progressively
    private func compressForUpload(image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        // Scale down if needed
        let scaledBitmap = scaleBitmap(bitmap, maxDimension: Self.maxImageDimension)

        // Try JPEG at decreasing quality until it fits
        let qualities: [Double] = [0.8, 0.6, 0.45, 0.3, 0.2]
        for quality in qualities {
            if let data = scaledBitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: quality]
            ), data.count <= Self.maxAttachmentBytes {
                return data
            }
        }

        // Last resort: scale down more aggressively
        let smallBitmap = scaleBitmap(bitmap, maxDimension: 600)
        return smallBitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.3]
        )
    }

    /// Scale a bitmap so its longest side is at most `maxDimension`.
    private func scaleBitmap(_ bitmap: NSBitmapImageRep, maxDimension: CGFloat) -> NSBitmapImageRep {
        let w = CGFloat(bitmap.pixelsWide)
        let h = CGFloat(bitmap.pixelsHigh)
        let longest = max(w, h)

        guard longest > maxDimension else { return bitmap }

        let scale = maxDimension / longest
        let newW = Int(w * scale)
        let newH = Int(h * scale)

        guard let resized = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: newW,
            pixelsHigh: newH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return bitmap }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
        NSGraphicsContext.current?.imageInterpolation = .high
        bitmap.draw(in: NSRect(x: 0, y: 0, width: newW, height: newH))
        NSGraphicsContext.restoreGraphicsState()

        return resized
    }

    // MARK: - Error mapping

    /// Map gateway errors to user-friendly messages.
    private static func userFriendlyError(_ error: Error) -> String {
        if let gwError = error as? GatewayClientError {
            switch gwError {
            case .cancelled:
                return "Connection lost — message not sent"
            case .notConnected:
                return "Not connected to gateway"
            case .timeout:
                return "Gateway request timed out"
            default:
                return gwError.localizedDescription
            }
        }
        if error is CancellationError {
            return "Request was cancelled"
        }
        return error.localizedDescription
    }
}
