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

    /// Pending image attachments to send with the next message.
    var pendingAttachments: [PendingAttachment] = []

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

    /// Display name of the active agent (from the connection profile).
    var agentDisplayName: String {
        appViewModel.connectionManager.activeProfile?.displayName ?? "Assistant"
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

        guard let client = appViewModel.connectionManager.activeClient else {
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

    // MARK: - Attachments

    /// Maximum attachment size in bytes (5 MB — gateway limit).
    private static let maxAttachmentBytes = 5_000_000

    /// Add an image from a file URL.
    func addAttachment(from url: URL) {
        guard let image = NSImage(contentsOf: url),
              let data = imageData(for: image, url: url) else {
            errorMessage = "Could not load image from file"
            return
        }
        let mimeType = mimeTypeForURL(url)
        guard data.count <= Self.maxAttachmentBytes else {
            errorMessage = "Image too large (max 5 MB)"
            return
        }
        let attachment = PendingAttachment(
            image: image,
            data: data,
            mimeType: mimeType,
            fileName: url.lastPathComponent
        )
        pendingAttachments.append(attachment)
    }

    /// Add an image from NSImage (e.g. pasted from clipboard).
    func addAttachment(image: NSImage, fileName: String? = nil) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            errorMessage = "Could not process pasted image"
            return
        }
        guard pngData.count <= Self.maxAttachmentBytes else {
            errorMessage = "Image too large (max 5 MB)"
            return
        }
        let attachment = PendingAttachment(
            image: image,
            data: pngData,
            mimeType: "image/png",
            fileName: fileName ?? "pasted-image.png"
        )
        pendingAttachments.append(attachment)
    }

    /// Remove a pending attachment.
    func removeAttachment(_ attachment: PendingAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    /// Get image data from a file, preferring the original format.
    private func imageData(for image: NSImage, url: URL) -> Data? {
        // Try reading the raw file data first (preserves JPEG compression, etc.)
        if let data = try? Data(contentsOf: url), data.count <= Self.maxAttachmentBytes {
            return data
        }
        // Fallback: re-encode as PNG
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
    }

    /// Determine MIME type from file URL.
    private func mimeTypeForURL(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "svg": return "image/svg+xml"
        default: return "image/png"
        }
    }
}
