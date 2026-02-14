import SwiftUI
import UniformTypeIdentifiers

/// Message input field with attachment support, send/abort buttons.
///
/// **Enter** sends the message, **Shift+Enter** inserts a newline.
/// Images can be attached via the paperclip button, drag-and-drop, or Cmd+V paste.
struct MessageComposer: View {
    @Binding var text: String
    let isSending: Bool
    let isStreaming: Bool
    let pendingAttachments: [PendingAttachment]
    var onSend: () -> Void
    var onAbort: () -> Void
    var onAddAttachment: (URL) -> Void
    var onPasteImage: (NSImage) -> Void
    var onRemoveAttachment: (PendingAttachment) -> Void

    @FocusState private var isFocused: Bool
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Attachment preview strip
            if !pendingAttachments.isEmpty {
                AttachmentPreviewStrip(
                    attachments: pendingAttachments,
                    onRemove: onRemoveAttachment
                )
            }

            HStack(alignment: .center, spacing: 10) {
                // Attach button
                Button(action: pickFile) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Attach image (⌘⇧A)")
                .keyboardShortcut("a", modifiers: [.command, .shift])

                // Text field — pill-shaped capsule like iMessage
                ComposerTextEditor(
                    text: $text,
                    onEnterSend: {
                        if canSend { onSend() }
                    },
                    onPasteImage: onPasteImage
                )
                .font(.body)
                .frame(height: 32)
                .padding(.horizontal, 12)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isDropTargeted
                                ? Color.accentColor
                                : Color(nsColor: .separatorColor).opacity(0.6),
                            lineWidth: isDropTargeted ? 2 : 1
                        )
                )
                .focused($isFocused)

                // Abort button (visible during streaming)
                if isStreaming {
                    Button(action: onAbort) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop generation (Esc)")
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .onAppear { isFocused = true }
    }

    private var canSend: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !pendingAttachments.isEmpty
        return (hasText || hasAttachments) && !isSending
    }

    // MARK: - File picker

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Select images to attach"

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            onAddAttachment(url)
        }
    }

    // MARK: - Drag and drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            // Try file URL first
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    let imageTypes = ["jpg", "jpeg", "png", "gif", "webp", "heic", "svg"]
                    guard imageTypes.contains(url.pathExtension.lowercased()) else { return }
                    DispatchQueue.main.async {
                        onAddAttachment(url)
                    }
                }
                handled = true
            }
            // Try inline image data
            else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                    var image: NSImage?
                    if let data = item as? Data {
                        image = NSImage(data: data)
                    } else if let url = item as? URL {
                        image = NSImage(contentsOf: url)
                    }
                    guard let img = image else { return }
                    DispatchQueue.main.async {
                        onPasteImage(img)
                    }
                }
                handled = true
            }
        }
        return handled
    }
}

// MARK: - Attachment Preview Strip

/// Horizontal strip showing pending attachment thumbnails with remove buttons.
struct AttachmentPreviewStrip: View {
    let attachments: [PendingAttachment]
    let onRemove: (PendingAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentThumbnail(attachment: attachment, onRemove: {
                        onRemove(attachment)
                    })
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }
}

/// A single attachment thumbnail with a remove button.
struct AttachmentThumbnail: View {
    let attachment: PendingAttachment
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: attachment.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )

            // Remove button — always visible on hover
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .background(Circle().fill(.black.opacity(0.6)).frame(width: 18, height: 18))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { isHovered = $0 }
        .help(attachment.fileName ?? "Image attachment")
    }
}

// MARK: - ComposerTextEditor (NSViewRepresentable)

/// A `TextEditor` replacement that intercepts Enter key presses and Cmd+V image paste.
///
/// - **Enter**: triggers `onEnterSend` (sends the message)
/// - **Shift+Enter** / **Option+Enter**: inserts a newline
/// - **Cmd+V** with image on clipboard: calls `onPasteImage`
struct ComposerTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onEnterSend: () -> Void
    var onPasteImage: (NSImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        // Vertically center single line: compute inset from frame height vs line height
        let lineHeight = (textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)).boundingRectForFont.height
        let verticalInset = max(0, (32 - lineHeight) / 2)
        textView.textContainerInset = NSSize(width: 0, height: verticalInset)

        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        // Only update if the text actually changed (avoids cursor jumps)
        if textView.string != text {
            textView.string = text
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextEditor
        weak var textView: NSTextView?

        init(parent: ComposerTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Check if Shift or Option is held → insert newline
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) || flags.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                // Plain Enter → send
                parent.onEnterSend()
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                // Shift+Enter or Option+Enter → insert newline
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            // Intercept Cmd+V to check for image paste
            if commandSelector == #selector(NSText.paste(_:)) {
                if handleImagePaste() {
                    return true
                }
                // Fall through to default paste for text
                return false
            }
            return false
        }

        /// Check if the pasteboard has an image and handle it.
        /// Returns true if an image was pasted (preventing default text paste).
        private func handleImagePaste() -> Bool {
            let pasteboard = NSPasteboard.general

            // Check for image data on pasteboard
            guard let imageType = pasteboard.availableType(from: [
                .png, .tiff,
                NSPasteboard.PasteboardType("public.jpeg"),
                NSPasteboard.PasteboardType("public.heic"),
            ]) else {
                // No image — also check if there's a file URL pointing to an image
                if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
                    .urlReadingContentsConformToTypes: [UTType.image.identifier]
                ]) as? [URL], let url = urls.first, let image = NSImage(contentsOf: url) {
                    parent.onPasteImage(image)
                    return true
                }
                return false
            }

            // We have image data
            if let data = pasteboard.data(forType: imageType),
               let image = NSImage(data: data) {
                parent.onPasteImage(image)
                return true
            }
            return false
        }
    }
}
