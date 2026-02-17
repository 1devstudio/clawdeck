import SwiftUI

// MARK: - Surface Style

/// How a themed surface is rendered: liquid glass, solid color, or translucent color.
enum SurfaceStyle: String, CaseIterable, Identifiable, Codable {
    case glass = "glass"
    case solid = "solid"
    case translucent = "translucent"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .glass: return "Glass"
        case .solid: return "Solid"
        case .translucent: return "Translucent"
        }
    }
}

// MARK: - Theme Config

/// Complete theme configuration, broken into logical groups.
/// Persisted via UserDefaults (prefixed with `theme.`).
struct ThemeConfig: Equatable {

    // ── 1. Chat Bubbles ──────────────────────────────────────────────
    var bubbleStyle: SurfaceStyle = .glass
    var userBubbleColorHex: String = "#007AFF"       // Blue tint
    var assistantBubbleColorHex: String = "#48484A"  // Dark gray tint
    var systemBubbleColorHex: String = "#FFD60A"     // Yellow

    // ── 2. Sidebar ───────────────────────────────────────────────────
    var sidebarStyle: SurfaceStyle = .glass
    var sidebarColorHex: String = "#2C2C2E"

    // ── 3. Composer (controls the input field pill + attach button) ──
    var composerStyle: SurfaceStyle = .glass
    var composerFieldColorHex: String = "#1C1C1E"
    var composerFieldBorderColorHex: String = "#3A3A3C"

    // ── 4. Tools Panel ───────────────────────────────────────────────
    var toolsPanelStyle: SurfaceStyle = .glass
    var toolsPanelColorHex: String = "#2C2C2E"
    var toolBlockColorHex: String = "#3A3A3C"

    // ── 5. Chrome ────────────────────────────────────────────────────
    var chromeUsesSystem: Bool = true
    var chromeColorHex: String = "#1C1C1E"

    // MARK: - Defaults

    static let `default` = ThemeConfig()
}

// MARK: - Environment Key

private struct ThemeConfigKey: EnvironmentKey {
    static let defaultValue: ThemeConfig = .default
}

extension EnvironmentValues {
    var themeConfig: ThemeConfig {
        get { self[ThemeConfigKey.self] }
        set { self[ThemeConfigKey.self] = newValue }
    }
}

// MARK: - Convenience Color Accessors

extension ThemeConfig {

    var sidebarColor: Color { Color(hex: sidebarColorHex) }
    var composerFieldColor: Color { Color(hex: composerFieldColorHex) }
    var composerFieldBorderColor: Color { Color(hex: composerFieldBorderColorHex) }
    var toolsPanelColor: Color { Color(hex: toolsPanelColorHex) }
    var toolBlockColor: Color { Color(hex: toolBlockColorHex) }

    /// Chrome color: system default or custom.
    var chromeColor: Color {
        chromeUsesSystem ? Color(nsColor: .windowBackgroundColor) : Color(hex: chromeColorHex)
    }
}

// MARK: - Luminance-based Color Scheme

extension Color {
    /// Perceived luminance (0 = black, 1 = white) using the standard formula.
    /// Returns `nil` if the color can't be resolved to sRGB components.
    var luminance: Double? {
        let nsColor = NSColor(self).usingColorSpace(.sRGB)
        guard let c = nsColor else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        // Relative luminance (ITU-R BT.709)
        return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }

    /// Returns `.light` if this color is bright (needs dark text),
    /// `.dark` if this color is dark (needs light text).
    var preferredColorScheme: ColorScheme {
        (luminance ?? 0) > 0.5 ? .light : .dark
    }
}
