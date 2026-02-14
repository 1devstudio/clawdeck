import SwiftUI

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
