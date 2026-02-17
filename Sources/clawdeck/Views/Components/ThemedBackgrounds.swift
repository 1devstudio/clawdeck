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

// MARK: - Composer Field Modifier

/// Applies themed background + border to the composer text field pill.
/// Glass: uses `.glassEffect`; Solid/Translucent: uses composerFieldColor.
struct ThemedComposerFieldModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isDropTargeted: Bool
    @Environment(\.themeConfig) private var theme
    @Environment(\.themeColor) private var themeColor
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        let adapted = content.environment(\.colorScheme, composerScheme)
        switch theme.composerStyle {
        case .glass:
            adapted
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            isDropTargeted ? themeColor : Color.clear,
                            lineWidth: isDropTargeted ? 2 : 0
                        )
                )
        case .solid:
            adapted
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(theme.composerFieldColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            isDropTargeted ? themeColor : theme.composerFieldBorderColor.opacity(0.6),
                            lineWidth: isDropTargeted ? 2 : 1
                        )
                )
        case .translucent:
            adapted
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(theme.composerFieldColor.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            isDropTargeted ? themeColor : theme.composerFieldBorderColor.opacity(0.6),
                            lineWidth: isDropTargeted ? 2 : 1
                        )
                )
        }
    }

    private var composerScheme: ColorScheme {
        switch theme.composerStyle {
        case .glass: return systemScheme
        case .solid, .translucent: return theme.composerFieldColor.preferredColorScheme
        }
    }
}

/// Applies themed background to the composer attach button.
struct ThemedComposerButtonModifier: ViewModifier {
    @Environment(\.themeConfig) private var theme
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        let adapted = content.environment(\.colorScheme, composerScheme)
        switch theme.composerStyle {
        case .glass:
            adapted.glassEffect(in: .circle)
        case .solid:
            adapted.background(theme.composerFieldColor, in: Circle())
        case .translucent:
            adapted.background(theme.composerFieldColor.opacity(0.5), in: Circle())
        }
    }

    private var composerScheme: ColorScheme {
        switch theme.composerStyle {
        case .glass: return systemScheme
        case .solid, .translucent: return theme.composerFieldColor.preferredColorScheme
        }
    }
}

extension View {
    /// Apply themed composer field background + border.
    func themedComposerField(cornerRadius: CGFloat, isDropTargeted: Bool) -> some View {
        modifier(ThemedComposerFieldModifier(cornerRadius: cornerRadius, isDropTargeted: isDropTargeted))
    }

    /// Apply themed composer button background.
    func themedComposerButton() -> some View {
        modifier(ThemedComposerButtonModifier())
    }
}

// MARK: - Themed Pill Background

extension View {
    /// Apply themed pill (capsule) background matching a surface style and color.
    @ViewBuilder
    func themedPill(style: SurfaceStyle, color: Color) -> some View {
        switch style {
        case .glass:
            self.glassEffect(.regular.tint(color.opacity(0.3)), in: .capsule)
        case .solid:
            self
                .background(Capsule().fill(color))
                .overlay(Capsule().stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5))
        case .translucent:
            self
                .background(Capsule().fill(color.opacity(0.35)))
                .overlay(Capsule().stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5))
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

/// Applies the correct background style and adaptive color scheme to a message bubble.
struct ThemedBubbleModifier: ViewModifier {
    let role: MessageRole
    @Environment(\.themeConfig) private var theme
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        let adapted = content.environment(\.colorScheme, bubbleScheme)
        switch theme.bubbleStyle {
        case .glass:
            adapted.glassEffect(glassStyle, in: .rect(cornerRadius: 12))
        case .solid:
            adapted.background(solidColor, in: RoundedRectangle(cornerRadius: 12))
        case .translucent:
            adapted.background(translucentColor, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var bubbleScheme: ColorScheme {
        switch theme.bubbleStyle {
        case .glass:
            return systemScheme
        case .solid, .translucent:
            return solidColor.preferredColorScheme
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

// MARK: - Adaptive Color Scheme

extension View {
    /// Override the color scheme for this view subtree based on background luminance.
    /// Glass surfaces keep the system scheme; solid/translucent derive from the color's brightness.
    func adaptiveColorScheme(style: SurfaceStyle, background: Color, systemScheme: ColorScheme) -> some View {
        let scheme: ColorScheme = {
            switch style {
            case .glass:
                return systemScheme
            case .solid, .translucent:
                return background.preferredColorScheme
            }
        }()
        return self.environment(\.colorScheme, scheme)
    }

    /// Apply color scheme for the chrome (window shell + toolbar).
    /// Always sets explicitly so toolbar items inherit it reliably.
    /// When `chromeUsesSystem` is true, passes through the resolved system scheme.
    /// When using a custom color, derives from the color's luminance.
    func chromeColorScheme(_ theme: ThemeConfig, systemScheme: ColorScheme) -> some View {
        let scheme: ColorScheme = theme.chromeUsesSystem
            ? systemScheme
            : Color(hex: theme.chromeColorHex).preferredColorScheme
        return self.environment(\.colorScheme, scheme)
    }
}
