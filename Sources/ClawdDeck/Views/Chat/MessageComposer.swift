import SwiftUI

/// Message input field with send/abort buttons.
///
/// **Enter** sends the message, **Shift+Enter** inserts a newline.
struct MessageComposer: View {
    @Binding var text: String
    let isSending: Bool
    let isStreaming: Bool
    var onSend: () -> Void
    var onAbort: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Text input — uses a key-intercepting wrapper so Enter sends
            ComposerTextEditor(text: $text, onEnterSend: {
                if canSend { onSend() }
            })
            .font(.body)
            .frame(minHeight: 36, maxHeight: 120)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .focused($isFocused)

            // Abort button (only visible during streaming)
            if isStreaming {
                Button(action: onAbort) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Stop generation (Esc)")
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onAppear { isFocused = true }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }
}

// MARK: - ComposerTextEditor (NSViewRepresentable)

/// A `TextEditor` replacement that intercepts Enter key presses.
///
/// - **Enter**: triggers `onEnterSend` (sends the message)
/// - **Shift+Enter** / **Option+Enter**: inserts a newline
struct ComposerTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onEnterSend: () -> Void

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
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

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
            return false
        }
    }
}
