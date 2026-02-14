import SwiftUI

/// Gateway configuration editor — raw JSON editing with save/revert.
struct GatewaySettingsView: View {
    @State private var viewModel: GatewaySettingsViewModel

    init(appViewModel: AppViewModel?) {
        _viewModel = State(initialValue: GatewaySettingsViewModel(appViewModel: appViewModel))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            Divider()

            if viewModel.isLoading {
                Spacer()
                ProgressView("Loading configuration…")
                Spacer()
            } else {
                // Editor area
                editorArea
            }

            Divider()

            // Footer bar with status + actions
            footerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if viewModel.configText.isEmpty {
                await viewModel.loadConfig()
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Image(systemName: "gearshape.2")
                .foregroundStyle(.secondary)

            if let path = viewModel.configPath {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Gateway Configuration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isDirty {
                Label("Modified", systemImage: "pencil.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Editor

    private var editorArea: some View {
        ZStack(alignment: .topTrailing) {
            // Validation messages above the editor
            VStack(spacing: 0) {
                if !viewModel.validationIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.validationIssues, id: \.self) { issue in
                            Label(issue, systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.1))
                }

                if !viewModel.validationWarnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.validationWarnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1))
                }

                // JSON editor
                JSONEditorView(text: $viewModel.configText)
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            // Status messages
            Group {
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if let success = viewModel.successMessage {
                    Label(success, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if !viewModel.configExists {
                    Label("No config file — edits will create one", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .lineLimit(2)

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.reload() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading || viewModel.isSaving)

                Button("Revert") {
                    viewModel.revert()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isDirty || viewModel.isSaving)

                Button {
                    Task { await viewModel.saveConfig() }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Save & Restart")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isDirty || viewModel.isSaving)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - JSON Editor (NSTextView wrapper)

/// A monospaced text editor with line numbers, suitable for JSON editing.
struct JSONEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isGrammarCheckingEnabled = false

        // Monospaced font
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.textColor

        // Tab + indentation
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = []
        paragraphStyle.defaultTabInterval = 28.0  // 2-space tab width at 13pt
        textView.defaultParagraphStyle = paragraphStyle

        // Background
        textView.backgroundColor = NSColor.textBackgroundColor

        // Layout
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false  // allow horizontal scroll
        textView.textContainer?.containerSize.width = CGFloat.greatestFiniteMagnitude
        textView.isHorizontallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Line numbers via ruler
        scrollView.rulersVisible = true
        scrollView.hasVerticalRuler = true
        let rulerView = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = rulerView

        scrollView.documentView = textView
        textView.delegate = context.coordinator
        textView.string = text

        // Apply syntax highlighting
        context.coordinator.applySyntaxHighlighting(textView: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update if the text has actually changed from outside
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.applySyntaxHighlighting(textView: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: JSONEditorView

        init(_ parent: JSONEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applySyntaxHighlighting(textView: textView)

            // Update line numbers
            if let scrollView = textView.enclosingScrollView,
               let ruler = scrollView.verticalRulerView as? LineNumberRulerView {
                ruler.needsDisplay = true
            }
        }

        /// Basic JSON syntax highlighting.
        func applySyntaxHighlighting(textView: NSTextView) {
            let text = textView.string
            let storage = textView.textStorage!
            let fullRange = NSRange(location: 0, length: (text as NSString).length)

            storage.beginEditing()

            // Reset to default
            storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: fullRange)

            // Highlight strings (keys and values)
            let stringPattern = "\"(?:[^\"\\\\]|\\\\.)*\""
            if let regex = try? NSRegularExpression(pattern: stringPattern) {
                let matches = regex.matches(in: text, range: fullRange)
                for match in matches {
                    // Check if this string is a key (followed by a colon)
                    let afterRange = NSRange(location: match.range.location + match.range.length, length: min(5, fullRange.length - match.range.location - match.range.length))
                    if afterRange.length > 0 {
                        let afterText = (text as NSString).substring(with: afterRange).trimmingCharacters(in: .whitespaces)
                        if afterText.hasPrefix(":") {
                            // It's a key
                            storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range)
                        } else {
                            // It's a string value
                            storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: match.range)
                        }
                    } else {
                        storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: match.range)
                    }
                }
            }

            // Highlight numbers
            let numberPattern = "(?<=[:,\\[\\s])\\s*(-?\\d+\\.?\\d*(?:[eE][+-]?\\d+)?)"
            if let regex = try? NSRegularExpression(pattern: numberPattern) {
                let matches = regex.matches(in: text, range: fullRange)
                for match in matches {
                    if match.numberOfRanges > 1 {
                        storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: match.range(at: 1))
                    }
                }
            }

            // Highlight booleans and null
            let keywordPattern = "\\b(true|false|null)\\b"
            if let regex = try? NSRegularExpression(pattern: keywordPattern) {
                let matches = regex.matches(in: text, range: fullRange)
                for match in matches {
                    storage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range)
                }
            }

            storage.endEditing()
        }
    }
}

// MARK: - Line Number Ruler

/// Simple line-number ruler for NSTextView.
class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 40

        // Observe text changes to redraw
        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification, object: textView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification, object: textView.enclosingScrollView?.contentView
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func textDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    @objc func boundsDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = textView.visibleRect
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let text = textView.string as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        var lineNumber = 1
        // Count lines before visible range
        text.enumerateSubstrings(in: NSRange(location: 0, length: visibleCharRange.location), options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            lineNumber += 1
        }

        // Draw visible line numbers
        text.enumerateSubstrings(in: visibleCharRange, options: [.byLines, .substringNotRequired]) { _, substringRange, _, _ in
            let glyphRange = layoutManager.glyphRange(forCharacterRange: substringRange, actualCharacterRange: nil)
            var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            lineRect.origin.y -= visibleRect.origin.y

            let lineStr = "\(lineNumber)" as NSString
            let strSize = lineStr.size(withAttributes: attrs)
            let x = self.ruleThickness - strSize.width - 6
            let y = lineRect.origin.y + (lineRect.height - strSize.height) / 2

            lineStr.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
            lineNumber += 1
        }
    }
}
