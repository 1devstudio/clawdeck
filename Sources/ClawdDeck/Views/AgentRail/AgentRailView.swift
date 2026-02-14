import SwiftUI
import AppKit

/// Narrow vertical rail showing agent avatars, like Slack's workspace switcher.
struct AgentRailView: View {
    let profiles: [ConnectionProfile]
    let activeProfileId: String?
    let connectionState: ConnectionState
    let onSelect: (ConnectionProfile) -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(profiles) { profile in
                        AgentRailItem(
                            profile: profile,
                            isActive: profile.id == activeProfileId,
                            isConnected: profile.id == activeProfileId && connectionState == .connected
                        )
                        .onTapGesture { onSelect(profile) }
                    }
                }
                .padding(.vertical, 8)
            }

            Spacer()

            Divider()
                .padding(.horizontal, 8)

            // Add agent button
            Button(action: onAdd) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Add Agent")
            .padding(.bottom, 8)
        }
        .frame(width: 60)
        .background(Color.clear)
    }
}

/// A single agent avatar in the rail.
struct AgentRailItem: View {
    let profile: ConnectionProfile
    let isActive: Bool
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Active indicator pill on the left edge
            RoundedRectangle(cornerRadius: 2)
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(width: 4, height: isActive ? 28 : 0)
                .animation(.easeInOut(duration: 0.15), value: isActive)

            Spacer()

            // Avatar
            ZStack {
                RoundedRectangle(cornerRadius: isActive ? 14 : 20)
                    .fill(isActive ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .animation(.easeInOut(duration: 0.15), value: isActive)

                agentAvatar
            }
            // Connection state ring
            .overlay(alignment: .bottomTrailing) {
                if isActive {
                    Circle()
                        .fill(isConnected ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
            }

            Spacer()
        }
        .frame(width: 60)
        .contentShape(Rectangle())
        .help(profile.displayName)
    }

    @ViewBuilder
    private var agentAvatar: some View {
        if let avatarName = profile.avatarName {
            if avatarName.hasPrefix("sf:") {
                // SF Symbol
                Image(systemName: String(avatarName.dropFirst(3)))
                    .font(.system(size: 18))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            } else {
                // Custom image from app support
                if let image = loadCustomAvatar(named: avatarName) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: isActive ? 12 : 18))
                } else {
                    initialsView
                }
            }
        } else {
            initialsView
        }
    }

    private var initialsView: some View {
        Text(profile.initials)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
    }

    /// Load a custom avatar image from the app's avatars directory.
    private func loadCustomAvatar(named filename: String) -> NSImage? {
        let avatarDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ClawdDeck/avatars")
        guard let url = avatarDir?.appendingPathComponent(filename) else { return nil }
        return NSImage(contentsOf: url)
    }
}