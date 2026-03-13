import SwiftUI

/// Compact pill button showing the current thinking level, with a popover to change it.
///
/// Placed next to the model selector above the composer.
/// Only visible when the current model supports reasoning.
struct ThinkingLevelPicker: View {
    /// Current thinking level for this session (nil = off/default).
    let currentLevel: String?

    /// Called when the user selects a level. Pass `nil` for off.
    let onSelect: (String?) -> Void

    @State private var isPopoverPresented = false
    @Environment(\.themeConfig) private var theme
    @Environment(\.colorScheme) private var systemScheme

    /// Available thinking levels with display labels.
    private static let levels: [(id: String?, label: String, icon: String)] = [
        (nil,        "Off",     "brain"),
        ("minimal",  "Minimal", "brain"),
        ("low",      "Low",     "brain"),
        ("medium",   "Medium",  "brain"),
        ("high",     "High",    "brain"),
    ]

    private var displayLabel: String {
        guard let level = currentLevel else { return "Thinking" }
        return Self.levels.first { $0.id == level }?.label ?? level.capitalized
    }

    private var isActive: Bool {
        currentLevel != nil
    }

    private var composerScheme: ColorScheme {
        switch theme.composerStyle {
        case .glass: return systemScheme
        case .solid, .translucent: return theme.composerFieldColor.preferredColorScheme
        }
    }

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                if isActive {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 10))
                        .foregroundStyle(.purple)
                } else {
                    Image(systemName: "brain")
                        .font(.system(size: 10))
                }
                Text(displayLabel)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? .purple : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .environment(\.colorScheme, composerScheme)
            .themedPill(style: theme.composerStyle, color: theme.composerFieldColor)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Thinking level")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Thinking Level")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                ForEach(Self.levels, id: \.label) { level in
                    let isSelected = currentLevel == level.id
                    Button {
                        isPopoverPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            onSelect(level.id)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundStyle(isSelected ? .purple : .secondary)
                                .frame(width: 16)

                            Text(level.label)
                                .font(.system(size: 12, weight: isSelected ? .medium : .regular))

                            Spacer()

                            if level.id != nil {
                                thinkingIntensityDots(level.id!)
                            }
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSelected ? Color.purple.opacity(0.08) : .clear)
                    )
                }
            }
            .padding(6)
            .frame(width: 200)
        }
    }

    /// Visual intensity indicator dots.
    private func thinkingIntensityDots(_ level: String) -> some View {
        let count: Int = switch level {
        case "minimal": 1
        case "low": 2
        case "medium": 3
        case "high": 4
        default: 0
        }

        return HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i < count ? Color.purple : Color.purple.opacity(0.15))
                    .frame(width: 5, height: 5)
            }
        }
    }
}
