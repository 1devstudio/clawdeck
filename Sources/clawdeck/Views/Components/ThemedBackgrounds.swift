import SwiftUI

// MARK: - Sidebar Background

/// Renders the sidebar background based on the current theme config.
struct ThemedSidebarBackground: View {
    @Environment(\.themeConfig) private var theme

    var body: some View {
        switch theme.sidebarStyle {
        case .glass:
            VisualEffectBlur(material: .sidebar)
        case .solid:
            Rectangle().fill(theme.sidebarColor)
        case .translucent:
            ZStack {
                VisualEffectBlur(material: .sidebar).opacity(0.3)
                Rectangle().fill(theme.sidebarColor.opacity(0.6))
            }
        }
    }
}

// MARK: - Tools Panel Background

/// Renders the tools panel background based on the current theme config.
struct ThemedToolsPanelBackground: View {
    @Environment(\.themeConfig) private var theme

    var body: some View {
        switch theme.toolsPanelStyle {
        case .glass:
            Rectangle().fill(.ultraThinMaterial)
        case .solid:
            Rectangle().fill(theme.toolsPanelColor)
        case .translucent:
            ZStack {
                Rectangle().fill(.ultraThinMaterial).opacity(0.3)
                Rectangle().fill(theme.toolsPanelColor.opacity(0.6))
            }
        }
    }
}

// MARK: - Themed Bubble Modifier

/// Applies the correct background style to a message bubble based on the theme.
struct ThemedBubbleModifier: ViewModifier {
    let role: MessageRole
    @Environment(\.themeConfig) private var theme

    func body(content: Content) -> some View {
        switch theme.bubbleStyle {
        case .glass:
            content.glassEffect(glassStyle, in: .rect(cornerRadius: 12))
        case .solid:
            content.background(solidColor, in: RoundedRectangle(cornerRadius: 12))
        case .translucent:
            content.background(translucentColor, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var glassStyle: Glass {
        switch role {
        case .user:
            return .regular.tint(Color(hex: theme.userBubbleColorHex).opacity(0.5))
        case .assistant:
            return .regular.tint(Color(hex: theme.assistantBubbleColorHex).opacity(0.3))
        case .system:
            return .regular.tint(Color(hex: theme.systemBubbleColorHex).opacity(0.3))
        case .toolCall, .toolResult:
            return .regular.tint(Color.gray.opacity(0.3))
        }
    }

    private var solidColor: Color {
        switch role {
        case .user: return Color(hex: theme.userBubbleColorHex)
        case .assistant: return Color(hex: theme.assistantBubbleColorHex)
        case .system: return Color(hex: theme.systemBubbleColorHex)
        case .toolCall, .toolResult: return Color(hex: theme.toolBlockColorHex)
        }
    }

    private var translucentColor: Color {
        switch role {
        case .user: return Color(hex: theme.userBubbleColorHex).opacity(0.35)
        case .assistant: return Color(hex: theme.assistantBubbleColorHex).opacity(0.35)
        case .system: return Color(hex: theme.systemBubbleColorHex).opacity(0.35)
        case .toolCall, .toolResult: return Color(hex: theme.toolBlockColorHex).opacity(0.35)
        }
    }
}

extension View {
    /// Apply themed bubble background based on message role and current theme.
    func themedBubble(for role: MessageRole) -> some View {
        modifier(ThemedBubbleModifier(role: role))
    }
}

// MARK: - Themed Tool Block Modifier

/// Applies the correct background to tool call blocks and thinking blocks.
struct ThemedToolBlockModifier: ViewModifier {
    @Environment(\.themeConfig) private var theme

    func body(content: Content) -> some View {
        switch theme.toolsPanelStyle {
        case .glass:
            content.glassEffect(.regular, in: .rect(cornerRadius: 8))
        case .solid:
            content.background(theme.toolBlockColor, in: RoundedRectangle(cornerRadius: 8))
        case .translucent:
            content.background(theme.toolBlockColor.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

extension View {
    /// Apply themed tool block background.
    func themedToolBlock() -> some View {
        modifier(ThemedToolBlockModifier())
    }
}
