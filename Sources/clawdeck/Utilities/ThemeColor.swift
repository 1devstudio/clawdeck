import SwiftUI
@preconcurrency import HighlightSwift

// MARK: - Appearance Mode

/// User's preferred appearance: dark, light, or follow the system default.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Theme Color Environment Key

/// Custom environment key for the app's accent/theme color.
/// Views should use `@Environment(\.themeColor)` instead of `Color.accentColor`
/// to respect the user's chosen accent color from Agent Settings.
private struct ThemeColorKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

extension EnvironmentValues {
    var themeColor: Color {
        get { self[ThemeColorKey.self] }
        set { self[ThemeColorKey.self] = newValue }
    }
}

// MARK: - Message Text Size Environment Key

private struct MessageTextSizeKey: EnvironmentKey {
    static let defaultValue: Double = 14
}

extension EnvironmentValues {
    var messageTextSize: Double {
        get { self[MessageTextSizeKey.self] }
        set { self[MessageTextSizeKey.self] = newValue }
    }
}

// MARK: - Code Highlight Theme Environment Key

private struct CodeHighlightThemeKey: EnvironmentKey {
    static let defaultValue: HighlightTheme = .github
}

extension EnvironmentValues {
    var codeHighlightTheme: HighlightTheme {
        get { self[CodeHighlightThemeKey.self] }
        set { self[CodeHighlightThemeKey.self] = newValue }
    }
}

// MARK: - Highlight Theme Keyword Color

extension HighlightTheme {
    /// The keyword color from this theme's CSS, suitable for inline code styling.
    func keywordColor(for colorScheme: ColorScheme) -> Color {
        let css = (colorScheme == .dark ? HighlightColors.dark(self) : HighlightColors.light(self)).css
        if let hex = Self.parseKeywordHex(from: css) {
            return Color(hex: hex)
        }
        return .purple
    }

    private static func parseKeywordHex(from css: String) -> String? {
        // Match a CSS rule whose selector contains ".hljs-keyword" and extract the color value.
        guard let regex = try? NSRegularExpression(
            pattern: #"\.hljs-keyword[^{]*\{[^}]*?color:\s*(#[0-9a-fA-F]{3,8})"#
        ) else { return nil }
        let range = NSRange(css.startIndex..., in: css)
        guard let match = regex.firstMatch(in: css, range: range),
              let hexRange = Range(match.range(at: 1), in: css) else { return nil }
        return String(css[hexRange])
    }
}

private extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let expanded: String
        if h.count == 3 {
            expanded = h.map { "\($0)\($0)" }.joined()
        } else {
            expanded = h
        }
        let scanner = Scanner(string: expanded)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
