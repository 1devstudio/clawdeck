import SwiftUI
import HighlightSwift

/// A view that displays a code block with syntax highlighting using highlight.js.
///
/// Uses HighlightSwift for language detection and colorization.
/// Shows a language badge and copy button in a styled card.
struct HighlightedCodeBlock: View {
    let code: String
    let language: String?

    @Environment(\.colorScheme) private var colorScheme
    @State private var highlightResult: AttributedString?
    @State private var detectedLanguage: String?
    @State private var isCopied = false

    private let highlight = Highlight()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar with language label and copy button
            HStack {
                Text(displayLanguage)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    copyToClipboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied" : "Copy")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(headerBackground)

            Divider()
                .opacity(0.5)

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Group {
                    if let highlighted = highlightResult {
                        Text(highlighted)
                            .font(.system(.callout, design: .monospaced))
                    } else {
                        Text(code)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(12)
                .textSelection(.enabled)
            }
        }
        .background(codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 0.5)
        )
        .task(id: code + (language ?? "")) {
            await performHighlight()
        }
    }

    // MARK: - Highlighting

    private func performHighlight() async {
        do {
            let colors: HighlightColors = colorScheme == .dark
                ? .dark(.githubDark)
                : .light(.github)

            let result: HighlightResult
            if let lang = language, !lang.isEmpty {
                result = try await highlight.request(code, mode: .languageAlias(lang), colors: colors)
            } else {
                result = try await highlight.request(code, mode: .automatic, colors: colors)
            }

            highlightResult = result.attributedText
            detectedLanguage = result.languageName
        } catch {
            // Fall back to plain text on error
            highlightResult = nil
        }
    }

    // MARK: - Actions

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        isCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            isCopied = false
        }
    }

    // MARK: - Computed properties

    private var displayLanguage: String {
        if let language, !language.isEmpty {
            return language.capitalized
        }
        if let detected = detectedLanguage, !detected.isEmpty {
            return detected
        }
        return "Code"
    }

    private var codeBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.09, blue: 0.10)
            : Color(red: 0.97, green: 0.97, blue: 0.98)
    }

    private var headerBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.13, blue: 0.15)
            : Color(red: 0.93, green: 0.93, blue: 0.95)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.1)
            : Color.black.opacity(0.1)
    }
}
