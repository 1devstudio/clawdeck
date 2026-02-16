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
    /// Incremented to programmatically focus the composer (e.g. via ⌘L).
    var focusTrigger: Int = 0
    var onSend: () -> Void
    var onAbort: () -> Void
    var onAddAttachment: (URL) -> Void
    @Environment(\.themeColor) private var themeColor
    @Environment(\.messageTextSize) private var messageTextSize
    var onPasteImage: (NSImage) -> Void
    var onRemoveAttachment: (PendingAttachment) -> Void

    @FocusState private var isFocused: Bool
    @State private var isDropTargeted = false
    @State private var editorHeight: CGFloat = 32

    var body: some View {
        VStack(spacing: 0) {
            // Attachment preview strip
            if !pendingAttachments.isEmpty {
                AttachmentPreviewStrip(
                    attachments: pendingAttachments,
                    onRemove: onRemoveAttachment
                )
            }

            HStack(alignment: .bottom, spacing: 10) {
                // Attach button
                Button(action: pickFile) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(in: .circle)
                .help("Attach image (⌘⇧A)")
                .keyboardShortcut("a", modifiers: [.command, .shift])

                // Text field — pill-shaped like iMessage
                ComposerTextEditor(
                    text: $text,
                    contentHeight: $editorHeight,
                    fontSize: messageTextSize,
                    onEnterSend: {
                        if canSend { onSend() }
                    },
                    onPasteImage: onPasteImage
                )
                .font(.system(size: messageTextSize))
                .frame(height: editorHeight)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: editorHeight <= 36 ? editorHeight / 2 : 18)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: editorHeight <= 36 ? editorHeight / 2 : 18)
                        .stroke(
                            isDropTargeted
                                ? themeColor
                                : Color(nsColor: .separatorColor).opacity(0.6),
                            lineWidth: isDropTargeted ? 2 : 1
                        )
                )
                .animation(.easeOut(duration: 0.15), value: editorHeight)
                .focused($isFocused)

                // Abort button (visible while waiting for or receiving a response)
                if isSending || isStreaming {
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
        .onChange(of: focusTrigger) { _, _ in
            isFocused = true
        }
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
    @Binding var contentHeight: CGFloat
    var fontSize: Double = 14
    var onEnterSend: () -> Void
    var onPasteImage: (NSImage) -> Void

    static let minHeight: CGFloat = 32
    static let maxHeight: CGFloat = 120

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.isSelectable = true
        textView.isEditable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 0, height: 6)

        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        context.coordinator.textView = textView

        // Observe frame changes to recalculate height
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.frameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
        textView.postsFrameChangedNotifications = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
            context.coordinator.recalcHeight(textView)
        }
        if textView.font?.pointSize != CGFloat(fontSize) {
            textView.font = NSFont.systemFont(ofSize: fontSize)
            context.coordinator.recalcHeight(textView)
        }
    }

    @MainActor class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextEditor
        weak var textView: NSTextView?

        init(parent: ComposerTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalcHeight(textView)
        }

        @objc func frameDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            recalcHeight(textView)
        }

        func recalcHeight(_ textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let inset = textView.textContainerInset
            let newHeight = min(
                max(usedRect.height + inset.height * 2, ComposerTextEditor.minHeight),
                ComposerTextEditor.maxHeight
            )
            DispatchQueue.main.async {
                if abs(self.parent.contentHeight - newHeight) > 0.5 {
                    self.parent.contentHeight = newHeight
                }
            }
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
