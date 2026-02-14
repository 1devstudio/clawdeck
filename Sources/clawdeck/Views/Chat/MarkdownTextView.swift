import SwiftUI
import AppKit
import HighlightSwift

/// An `NSTextView`-based markdown renderer that supports full cross-paragraph
/// text selection — unlike SwiftUI's `Markdown` view where each block element
/// is a separate view and selection is confined to a single paragraph.
///
/// Converts markdown text to `NSAttributedString` with styling for:
/// - Bold, italic, strikethrough, inline code
/// - Headings (H1–H6)
/// - Ordered and unordered lists (nested)
/// - Fenced code blocks with syntax highlighting (via HighlightSwift)
/// - Block quotes
/// - Links (clickable)
/// - Horizontal rules
struct MarkdownTextView: NSViewRepresentable {
    let markdown: String

    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> MarkdownNSTextView {
        let textView = MarkdownNSTextView()

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticLinkDetectionEnabled = false
        textView.autoresizingMask = [.width]
        // Don't clip — let the text view size itself
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.required, for: .vertical)

        context.coordinator.textView = textView
        context.coordinator.render(markdown: markdown, colorScheme: colorScheme)

        return textView
    }

    func updateNSView(_ textView: MarkdownNSTextView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.lastMarkdown != markdown || coordinator.lastColorScheme != colorScheme {
            coordinator.render(markdown: markdown, colorScheme: colorScheme)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator {
        weak var textView: MarkdownNSTextView?
        var lastMarkdown: String = ""
        var lastColorScheme: ColorScheme?
        private let highlight = Highlight()

        func render(markdown: String, colorScheme: ColorScheme) {
            lastMarkdown = markdown
            lastColorScheme = colorScheme

            guard let textView else { return }

            let result = MarkdownParser.parseWithRegions(markdown, colorScheme: colorScheme)
            textView.textStorage?.setAttributedString(result.attributedString)
            textView.codeBlockRegions = result.codeBlockRegions
            textView.invalidateIntrinsicContentSize()

            // Async: apply syntax highlighting to code blocks
            Task { @MainActor in
                await self.highlightCodeBlocks(in: markdown, colorScheme: colorScheme)
            }
        }

        /// Apply syntax highlighting to code blocks using tracked regions.
        @MainActor
        private func highlightCodeBlocks(in markdown: String, colorScheme: ColorScheme) async {
            guard let textView, let textStorage = textView.textStorage else { return }
            guard !textView.codeBlockRegions.isEmpty else { return }

            let colors: HighlightColors = colorScheme == .dark
                ? .dark(.github)
                : .light(.github)

            let monoFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
            let bgColor: NSColor = colorScheme == .dark
                ? NSColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1.0)
                : NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1.0)
            let codeParaStyle = NSMutableParagraphStyle()
            codeParaStyle.lineSpacing = 2

            for region in textView.codeBlockRegions {
                guard region.codeRange.location + region.codeRange.length <= textStorage.length else { continue }

                do {
                    let result: HighlightResult
                    if let lang = region.language, !lang.isEmpty {
                        result = try await highlight.request(region.code, mode: .languageAlias(lang), colors: colors)
                    } else {
                        result = try await highlight.request(region.code, mode: .automatic, colors: colors)
                    }

                    // Convert SwiftUI AttributedString to NSAttributedString
                    let nsAttr = NSMutableAttributedString(result.attributedText)

                    // Preserve monospaced font, background, and paragraph style
                    nsAttr.addAttributes([
                        .font: monoFont,
                        .backgroundColor: bgColor,
                        .paragraphStyle: codeParaStyle
                    ], range: NSRange(location: 0, length: nsAttr.length))

                    // Apply to the code portion only (not the header)
                    textStorage.replaceCharacters(in: region.codeRange, with: nsAttr)
                    textView.invalidateIntrinsicContentSize()
                } catch {
                    // Keep the plain monospaced text on error
                }
            }
        }
    }
}

// MARK: - Self-sizing NSTextView with code block hover

/// Tracks the range and raw source of a code block in the attributed string.
struct CodeBlockRegion {
    let range: NSRange       // Range in the text storage (includes header)
    let codeRange: NSRange   // Range of just the code (for highlighting replacement)
    let code: String         // Raw source code
    let language: String?    // Language tag (if any)
}

/// An `NSTextView` subclass that:
/// - Calculates its own `intrinsicContentSize` for SwiftUI layout
/// - Shows a floating "Copy" button when hovering over code blocks
/// - Adds a "Copy Code Block" context menu item
final class MarkdownNSTextView: NSTextView {

    /// Code block regions set by the coordinator after rendering.
    var codeBlockRegions: [CodeBlockRegion] = []

    /// The floating copy button (created lazily).
    private lazy var copyButton: NSButton = {
        let btn = NSButton(title: "Copy", target: self, action: #selector(copyHoveredCodeBlock))
        btn.bezelStyle = .recessed
        btn.controlSize = .small
        btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        btn.isBordered = true
        btn.isHidden = true
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 4
        btn.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9).cgColor
        addSubview(btn)
        return btn
    }()

    /// The code block currently being hovered (for copy action).
    private var hoveredCodeBlock: CodeBlockRegion?

    /// Tracking area for mouse movement.
    private var hoverTrackingArea: NSTrackingArea?

    // MARK: - Intrinsic sizing

    override var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: ceil(usedRect.height + textContainerInset.height * 2)
        )
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - Tracking area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    // MARK: - Mouse hover

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHover(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideCodeCopyButton()
    }

    private func updateHover(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        guard let layoutManager = layoutManager,
              let textContainer = textContainer else {
            hideCodeCopyButton()
            return
        }

        // Find character index at mouse position
        let textContainerOrigin = NSPoint(
            x: textContainerInset.width,
            y: textContainerInset.height
        )
        let adjustedPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )

        let charIndex = layoutManager.characterIndex(
            for: adjustedPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )

        // Check if the character is inside any code block region
        if let region = codeBlockRegions.first(where: { NSLocationInRange(charIndex, $0.range) }) {
            hoveredCodeBlock = region
            showCodeCopyButton(for: region)
        } else {
            hideCodeCopyButton()
        }
    }

    private func showCodeCopyButton(for region: CodeBlockRegion) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        // Get the bounding rect of the code block's first line for positioning
        var glyphRange = NSRange()
        layoutManager.characterRange(
            forGlyphRange: layoutManager.glyphRange(
                forCharacterRange: NSRange(location: region.range.location, length: 1),
                actualCharacterRange: nil
            ),
            actualGlyphRange: &glyphRange
        )

        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        let buttonSize = copyButton.fittingSize

        // Position in top-right of the code block
        copyButton.frame = NSRect(
            x: bounds.width - buttonSize.width - 8,
            y: lineRect.origin.y + textContainerInset.height + 4,
            width: buttonSize.width,
            height: buttonSize.height
        )
        copyButton.isHidden = false
    }

    private func hideCodeCopyButton() {
        hoveredCodeBlock = nil
        copyButton.isHidden = true
    }

    @objc private func copyHoveredCodeBlock() {
        guard let region = hoveredCodeBlock else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(region.code, forType: .string)

        // Briefly show "Copied" feedback
        let originalTitle = copyButton.title
        copyButton.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.title = originalTitle
        }
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()

        // Check if right-click is inside a code block
        let point = convert(event.locationInWindow, from: nil)
        if let layoutManager = layoutManager, let textContainer = textContainer {
            let adjustedPoint = NSPoint(
                x: point.x - textContainerInset.width,
                y: point.y - textContainerInset.height
            )
            let charIndex = layoutManager.characterIndex(
                for: adjustedPoint,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
            if let region = codeBlockRegions.first(where: { NSLocationInRange(charIndex, $0.range) }) {
                hoveredCodeBlock = region

                // Insert "Copy Code Block" at the top
                let item = NSMenuItem(
                    title: "Copy Code Block",
                    action: #selector(copyHoveredCodeBlock),
                    keyEquivalent: ""
                )
                item.target = self
                menu.insertItem(item, at: 0)
                menu.insertItem(.separator(), at: 1)
            }
        }

        return menu
    }
}

// MARK: - Markdown Parser

/// Parses markdown text into `NSAttributedString` with proper styling.
///
/// This is a line-based parser that handles the most common markdown constructs.
/// It does NOT aim to be a full CommonMark parser — it covers what chat messages
/// typically use: paragraphs, bold/italic, code, lists, headings, quotes, links.
enum MarkdownParser {

    struct CodeBlock {
        let language: String?
        let code: String
    }

    /// Result of parsing markdown, including the attributed string and code block regions.
    struct ParseResult {
        let attributedString: NSAttributedString
        let codeBlockRegions: [CodeBlockRegion]
    }

    /// Parse markdown into a styled `NSAttributedString` and track code block regions.
    static func parseWithRegions(_ markdown: String, colorScheme: ColorScheme) -> ParseResult {
        var regions: [CodeBlockRegion] = []
        let attributed = parse(markdown, colorScheme: colorScheme, regions: &regions)
        return ParseResult(attributedString: attributed, codeBlockRegions: regions)
    }

    /// Parse markdown into a styled `NSAttributedString` (without region tracking).
    static func parse(_ markdown: String, colorScheme: ColorScheme) -> NSAttributedString {
        var regions: [CodeBlockRegion] = []
        return parse(markdown, colorScheme: colorScheme, regions: &regions)
    }

    /// Parse markdown into a styled `NSAttributedString`.
    static func parse(_ markdown: String, colorScheme: ColorScheme, regions: inout [CodeBlockRegion]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")

        let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textColor = NSColor.labelColor

        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: textColor,
            .paragraphStyle: defaultParagraphStyle()
        ]

        var i = 0
        /// Whether we've already appended at least one block.
        var hasContent = false

        /// Append a single newline separator between blocks.
        func blockSeparator() {
            if hasContent {
                result.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
            }
        }

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                blockSeparator()

                let language = String(line.trimmingCharacters(in: .whitespaces).dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                let code = codeLines.joined(separator: "\n")
                let regionStart = result.length
                let styledBlock = styledCodeBlock(code, language: language.isEmpty ? nil : language, colorScheme: colorScheme)
                result.append(styledBlock)

                // Track the region: full range includes header, codeRange is just the code
                let lang = language.isEmpty ? nil : language
                let headerLength = (lang ?? "Code").capitalized.count + 1 // +1 for \n
                let codeStart = regionStart + headerLength
                regions.append(CodeBlockRegion(
                    range: NSRange(location: regionStart, length: styledBlock.length),
                    codeRange: NSRange(location: codeStart, length: code.utf16.count),
                    code: code,
                    language: lang
                ))
                hasContent = true
                continue
            }

            // Blank line — skip (spacing handled by paragraphSpacing)
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }

            // Heading
            if let (level, text) = parseHeading(line) {
                blockSeparator()
                result.append(styledHeading(text, level: level, colorScheme: colorScheme))
                hasContent = true
                i += 1
                continue
            }

            // Horizontal rule
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 3 && (trimmed.allSatisfy({ $0 == "-" }) || trimmed.allSatisfy({ $0 == "*" }) || trimmed.allSatisfy({ $0 == "_" })) {
                blockSeparator()
                result.append(styledHorizontalRule(colorScheme: colorScheme))
                hasContent = true
                i += 1
                continue
            }

            // Block quote
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                blockSeparator()
                var quoteLines: [String] = []
                while i < lines.count {
                    let ql = lines[i].trimmingCharacters(in: .whitespaces)
                    if ql.hasPrefix("> ") {
                        quoteLines.append(String(ql.dropFirst(2)))
                    } else if ql == ">" {
                        quoteLines.append("")
                    } else {
                        break
                    }
                    i += 1
                }
                result.append(styledBlockQuote(quoteLines.joined(separator: "\n"), colorScheme: colorScheme))
                hasContent = true
                continue
            }

            // Unordered list item
            if let (indent, text) = parseUnorderedListItem(line) {
                var listItems: [(Int, String)] = [(indent, text)]
                i += 1
                while i < lines.count {
                    if let (nextIndent, nextText) = parseUnorderedListItem(lines[i]) {
                        listItems.append((nextIndent, nextText))
                        i += 1
                    } else if lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                        break
                    } else {
                        break
                    }
                }
                blockSeparator()
                for (itemIndex, (indent, itemText)) in listItems.enumerated() {
                    let bullet = indent > 0 ? "◦ " : "• "
                    let prefix = String(repeating: "    ", count: indent) + bullet
                    let line = NSMutableAttributedString(string: prefix, attributes: defaultAttrs)
                    line.append(parseInlineFormatting(itemText, baseAttrs: defaultAttrs))
                    if itemIndex < listItems.count - 1 {
                        line.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
                    }
                    result.append(line)
                }
                hasContent = true
                continue
            }

            // Ordered list item
            if let (indent, number, text) = parseOrderedListItem(line) {
                var listItems: [(Int, Int, String)] = [(indent, number, text)]
                i += 1
                while i < lines.count {
                    if let (nextIndent, nextNum, nextText) = parseOrderedListItem(lines[i]) {
                        listItems.append((nextIndent, nextNum, nextText))
                        i += 1
                    } else if lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                        break
                    } else {
                        break
                    }
                }
                blockSeparator()
                for (itemIndex, (indent, number, itemText)) in listItems.enumerated() {
                    let prefix = String(repeating: "    ", count: indent) + "\(number). "
                    let line = NSMutableAttributedString(string: prefix, attributes: defaultAttrs)
                    line.append(parseInlineFormatting(itemText, baseAttrs: defaultAttrs))
                    if itemIndex < listItems.count - 1 {
                        line.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
                    }
                    result.append(line)
                }
                hasContent = true
                continue
            }

            // Regular paragraph — collect consecutive non-blank, non-special lines
            var paraLines: [String] = [line]
            i += 1
            while i < lines.count {
                let next = lines[i]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty || nextTrimmed.hasPrefix("```") ||
                   nextTrimmed.hasPrefix("# ") || nextTrimmed.hasPrefix("## ") ||
                   nextTrimmed.hasPrefix("> ") || parseUnorderedListItem(next) != nil ||
                   parseOrderedListItem(next) != nil {
                    break
                }
                paraLines.append(next)
                i += 1
            }

            blockSeparator()
            let paraText = paraLines.joined(separator: " ")
            result.append(parseInlineFormatting(paraText, baseAttrs: defaultAttrs))
            hasContent = true
        }

        return result
    }

    // MARK: - Inline formatting

    /// Parse inline markdown (bold, italic, code, links, strikethrough).
    static func parseInlineFormatting(_ text: String, baseAttrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let scanner = Scanner(string: text)
        scanner.charactersToBeSkipped = nil

        let bodyFont = baseAttrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)

        while !scanner.isAtEnd {
            // Inline code: `code`
            if scanner.scanString("`") != nil {
                if let code = scanner.scanUpToString("`") {
                    _ = scanner.scanString("`")
                    let codeFont = NSFont.monospacedSystemFont(ofSize: bodyFont.pointSize - 1, weight: .regular)
                    let codeAttrs: [NSAttributedString.Key: Any] = [
                        .font: codeFont,
                        .foregroundColor: NSColor.systemPurple,
                        .backgroundColor: NSColor.systemPurple.withAlphaComponent(0.12)
                    ]
                    result.append(NSAttributedString(string: code, attributes: codeAttrs))
                } else {
                    result.append(NSAttributedString(string: "`", attributes: baseAttrs))
                }
                continue
            }

            // Link: [text](url)
            if scanner.scanString("[") != nil {
                if let linkText = scanner.scanUpToString("]("),
                   scanner.scanString("](") != nil,
                   let url = scanner.scanUpToString(")"),
                   scanner.scanString(")") != nil {
                    var linkAttrs = baseAttrs
                    linkAttrs[.foregroundColor] = NSColor.linkColor
                    linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    if let linkUrl = URL(string: url) {
                        linkAttrs[.link] = linkUrl
                    }
                    result.append(NSAttributedString(string: linkText, attributes: linkAttrs))
                } else {
                    result.append(NSAttributedString(string: "[", attributes: baseAttrs))
                }
                continue
            }

            // Bold+Italic: ***text*** or ___text___
            if scanner.scanString("***") != nil || scanner.scanString("___") != nil {
                let delim = text.contains("***") ? "***" : "___"
                if let content = scanner.scanUpToString(delim) {
                    _ = scanner.scanString(delim)
                    var attrs = baseAttrs
                    let boldItalicFont = NSFont.systemFont(ofSize: bodyFont.pointSize, weight: .bold)
                    if let italic = NSFontManager.shared.convert(boldItalicFont, toHaveTrait: .italicFontMask) as NSFont? {
                        attrs[.font] = italic
                    } else {
                        attrs[.font] = boldItalicFont
                        attrs[.obliqueness] = 0.2
                    }
                    result.append(NSAttributedString(string: content, attributes: attrs))
                }
                continue
            }

            // Bold: **text** or __text__
            if scanner.scanString("**") != nil {
                if let content = scanner.scanUpToString("**") {
                    _ = scanner.scanString("**")
                    var attrs = baseAttrs
                    attrs[.font] = NSFont.systemFont(ofSize: bodyFont.pointSize, weight: .bold)
                    result.append(parseInlineFormatting(content, baseAttrs: attrs))
                } else {
                    result.append(NSAttributedString(string: "**", attributes: baseAttrs))
                }
                continue
            }

            if scanner.scanString("__") != nil {
                if let content = scanner.scanUpToString("__") {
                    _ = scanner.scanString("__")
                    var attrs = baseAttrs
                    attrs[.font] = NSFont.systemFont(ofSize: bodyFont.pointSize, weight: .bold)
                    result.append(parseInlineFormatting(content, baseAttrs: attrs))
                } else {
                    result.append(NSAttributedString(string: "__", attributes: baseAttrs))
                }
                continue
            }

            // Italic: *text* or _text_ (single)
            if scanner.scanString("*") != nil {
                if let content = scanner.scanUpToString("*") {
                    _ = scanner.scanString("*")
                    var attrs = baseAttrs
                    if let italicFont = NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask) as NSFont? {
                        attrs[.font] = italicFont
                    } else {
                        attrs[.obliqueness] = 0.2
                    }
                    result.append(parseInlineFormatting(content, baseAttrs: attrs))
                } else {
                    result.append(NSAttributedString(string: "*", attributes: baseAttrs))
                }
                continue
            }

            // Strikethrough: ~~text~~
            if scanner.scanString("~~") != nil {
                if let content = scanner.scanUpToString("~~") {
                    _ = scanner.scanString("~~")
                    var attrs = baseAttrs
                    attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    result.append(NSAttributedString(string: content, attributes: attrs))
                } else {
                    result.append(NSAttributedString(string: "~~", attributes: baseAttrs))
                }
                continue
            }

            // Regular text — scan until next special character
            let specials = CharacterSet(charactersIn: "`[*_~")
            if let plain = scanner.scanUpToCharacters(from: specials) {
                result.append(NSAttributedString(string: plain, attributes: baseAttrs))
            } else {
                // Single special char that doesn't match a pattern — emit as-is
                let idx = text.index(text.startIndex, offsetBy: scanner.currentIndex.utf16Offset(in: text), limitedBy: text.endIndex) ?? text.endIndex
                if idx < text.endIndex {
                    let ch = String(text[idx])
                    result.append(NSAttributedString(string: ch, attributes: baseAttrs))
                    scanner.currentIndex = text.index(after: idx)
                } else {
                    break
                }
            }
        }

        return result
    }

    // MARK: - Block styles

    static func styledCodeBlock(_ code: String, language: String?, colorScheme: ColorScheme) -> NSAttributedString {
        // Fallback for code blocks rendered inline (normally handled by HighlightedCodeBlock)
        let monoFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
        let bgColor: NSColor = colorScheme == .dark
            ? NSColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1.0)
            : NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1.0)

        let codeParaStyle = NSMutableParagraphStyle()
        codeParaStyle.lineSpacing = 2

        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: bgColor,
            .paragraphStyle: codeParaStyle
        ]

        return NSAttributedString(string: code, attributes: codeAttrs)
    }

    static func styledHeading(_ text: String, level: Int, colorScheme: ColorScheme) -> NSAttributedString {
        let sizes: [CGFloat] = [24, 20, 17, 15, 14, 13]
        let size = level <= sizes.count ? sizes[level - 1] : NSFont.systemFontSize

        let font = NSFont.systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold)
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.paragraphSpacingBefore = level <= 2 ? 8 : 4

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paraStyle
        ]

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paraStyle
        ]

        return parseInlineFormatting(text, baseAttrs: baseAttrs)
    }

    static func styledBlockQuote(_ text: String, colorScheme: ColorScheme) -> NSAttributedString {
        let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let quoteColor: NSColor = .secondaryLabelColor

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.headIndent = 16
        paraStyle.firstLineHeadIndent = 16

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask),
            .foregroundColor: quoteColor,
            .paragraphStyle: paraStyle
        ]

        return NSAttributedString(string: "┃ " + text.replacingOccurrences(of: "\n", with: "\n┃ "), attributes: attrs)
    }

    static func styledHorizontalRule(colorScheme: ColorScheme) -> NSAttributedString {
        let ruleColor: NSColor = colorScheme == .dark
            ? NSColor.separatorColor
            : NSColor.separatorColor
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: ruleColor,
            .font: NSFont.systemFont(ofSize: 4)
        ]
        return NSAttributedString(string: "─────────────────────────────────", attributes: attrs)
    }

    // MARK: - Line parsing helpers

    static func parseHeading(_ line: String) -> (Int, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1 && level <= 6 else { return nil }
        guard trimmed.count > level && trimmed[trimmed.index(trimmed.startIndex, offsetBy: level)] == " " else {
            return nil
        }
        let text = String(trimmed.dropFirst(level + 1))
        return (level, text)
    }

    static func parseUnorderedListItem(_ line: String) -> (Int, String)? {
        let indent = line.prefix(while: { $0 == " " }).count / 2
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["- ", "* ", "+ "] {
            if trimmed.hasPrefix(prefix) {
                return (indent, String(trimmed.dropFirst(prefix.count)))
            }
        }
        return nil
    }

    static func parseOrderedListItem(_ line: String) -> (Int, Int, String)? {
        let indent = line.prefix(while: { $0 == " " }).count / 2
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dotIdx = trimmed.firstIndex(of: ".") else { return nil }
        let numStr = String(trimmed[trimmed.startIndex..<dotIdx])
        guard let num = Int(numStr), trimmed.count > numStr.count + 2 else { return nil }
        let afterDot = trimmed.index(after: dotIdx)
        guard afterDot < trimmed.endIndex && trimmed[afterDot] == " " else { return nil }
        let text = String(trimmed[trimmed.index(afterDot, offsetBy: 1)...])
        return (indent, num, text)
    }

    static func defaultParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = 6   // Space after each paragraph block
        return style
    }

    // MARK: - Code block extraction (for async highlighting)

    /// Extract fenced code blocks from markdown source.
    static func extractCodeBlocks(from markdown: String) -> [CodeBlock] {
        var blocks: [CodeBlock] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                let code = codeLines.joined(separator: "\n")
                if !code.isEmpty {
                    blocks.append(CodeBlock(language: language.isEmpty ? nil : language, code: code))
                }
                continue
            }
            i += 1
        }
        return blocks
    }

    /// Find the NSRange of a code block's text within the full rendered string.
    static func findCodeBlockRange(code: String, in fullString: String) -> NSRange? {
        guard let range = fullString.range(of: code) else { return nil }
        return NSRange(range, in: fullString)
    }
}
