import SwiftUI

/// Splits a markdown string into alternating text and code-block segments,
/// rendering text in `MarkdownTextView` (full cross-paragraph selection) and
/// code blocks in `HighlightedCodeBlock` (proper card styling).
struct MessageContentView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        MarkdownTextView(markdown: text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .code(let code, let language):
                    HighlightedCodeBlock(code: code, language: language)
                }
            }
        }
    }

    // MARK: - Segment parsing

    private enum Segment {
        case text(String)
        case code(String, String?)
    }

    /// Split markdown into text and fenced code block segments.
    private var segments: [Segment] {
        Self.parseSegments(from: markdown)
    }

    static func parseSegments(from markdown: String) -> [Segment] {
        var segments: [Segment] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        var currentTextLines: [String] = []

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                // Flush accumulated text
                if !currentTextLines.isEmpty {
                    segments.append(.text(currentTextLines.joined(separator: "\n")))
                    currentTextLines = []
                }

                // Extract language hint
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
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
                segments.append(.code(code, lang.isEmpty ? nil : lang))
            } else {
                currentTextLines.append(lines[i])
                i += 1
            }
        }

        // Flush remaining text
        if !currentTextLines.isEmpty {
            segments.append(.text(currentTextLines.joined(separator: "\n")))
        }

        return segments
    }
}
