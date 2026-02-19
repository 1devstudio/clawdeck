import SwiftUI
import AppKit

/// Narrow vertical rail showing agent avatars, like Slack's workspace switcher.
struct AgentRailView: View {
    let bindings: [AgentBinding]
    let activeBindingId: String?
    let gatewayManager: GatewayManager
    let onSelect: (AgentBinding) -> Void
    let onAddBinding: (AgentBinding) -> Void
    let onConnectNewGateway: () -> Void
    let onSettings: (AgentBinding) -> Void

    @State private var showAddPopover = false

    var body: some View {
        VStack(spacing: 4) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(bindings) { binding in
                        AgentRailItem(
                            binding: binding,
                            gatewayManager: gatewayManager,
                            isActive: binding.id == activeBindingId,
                            isConnected: gatewayManager.isConnected(binding.gatewayId),
                            onSelect: { onSelect(binding) },
                            onSettings: { onSettings(binding) }
                        )
                        .contextMenu {
                            AgentContextMenu(
                                binding: binding,
                                gatewayManager: gatewayManager,
                                onSettings: { onSettings(binding) }
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Spacer()

            Divider()
                .padding(.horizontal, 8)

            // Add agent button
            Button {
                showAddPopover = true
            } label: {
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
            .popover(isPresented: $showAddPopover) {
                AddAgentPopover(
                    gatewayManager: gatewayManager,
                    onAddBinding: { binding in
                        showAddPopover = false
                        onAddBinding(binding)
                    },
                    onConnectNewGateway: {
                        showAddPopover = false
                        onConnectNewGateway()
                    }
                )
            }
            .padding(.bottom, 8)
        }
        .frame(width: 60)
    }
}

/// A single agent avatar in the rail.
struct AgentRailItem: View {
    let binding: AgentBinding
    let gatewayManager: GatewayManager
    let isActive: Bool
    let isConnected: Bool
    let onSelect: () -> Void
    let onSettings: () -> Void
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        VStack(spacing: 10) {
            Button {
                onSelect()
            } label: {
                HStack(spacing: 0) {
                    // Active indicator pill on the left edge
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isActive ? themeColor : Color.clear)
                        .frame(width: 4, height: isActive ? 28 : 0)
                        .animation(.easeInOut(duration: 0.15), value: isActive)

                    Spacer()

                    // Avatar
                    ZStack {
                        RoundedRectangle(cornerRadius: isActive ? 14 : 20)
                            .fill(isActive ? themeColor.opacity(0.2) : Color.gray.opacity(0.15))
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
            }
            .buttonStyle(.borderless)
            .help(binding.displayName(from: gatewayManager))

            // Settings gear icon — only visible for the active agent
            if isActive {
                Button {
                    onSettings()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Agent Settings")
                .transition(.opacity.combined(with: .scale(scale: 0.5, anchor: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }

    @ViewBuilder
    private var agentAvatar: some View {
        if let avatarName = binding.avatarName(from: gatewayManager) {
            if avatarName.hasPrefix("sf:") {
                // SF Symbol
                Image(systemName: String(avatarName.dropFirst(3)))
                    .font(.system(size: 18))
                    .foregroundStyle(isActive ? themeColor : Color.secondary)
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
        Text(binding.initials(from: gatewayManager))
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(isActive ? themeColor : Color.secondary)
    }

    /// Load a custom avatar image from the app's avatars directory.
    private func loadCustomAvatar(named filename: String) -> NSImage? {
        let avatarDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("clawdeck/avatars")
        guard let url = avatarDir?.appendingPathComponent(filename) else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// Context menu for agent rail items.
struct AgentContextMenu: View {
    let binding: AgentBinding
    let gatewayManager: GatewayManager
    let onSettings: () -> Void

    private var gatewayProfile: GatewayProfile? {
        gatewayManager.gatewayProfiles.first { $0.id == binding.gatewayId }
    }

    var body: some View {
        VStack(alignment: .leading) {
            // Agent name (label)
            Text(binding.displayName(from: gatewayManager))
                .font(.headline)

            // Gateway address (dimmed label)
            if let gateway = gatewayProfile {
                Text(gateway.displayAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Agent Settings…") {
                onSettings()
            }

            Button("Gateway Settings…") {
                // TODO: Open gateway settings
            }

            Divider()

            Button("Remove from Sidebar") {
                gatewayManager.removeAgentBinding(binding)
            }
        }
    }
}

/// Popover for adding new agent bindings.
struct AddAgentPopover: View {
    let gatewayManager: GatewayManager
    let onAddBinding: (AgentBinding) -> Void
    let onConnectNewGateway: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Agent")
                .font(.headline)

            let availableAgents = gatewayManager.getAvailableAgents()
            
            if availableAgents.isEmpty {
                VStack(spacing: 8) {
                    Text("No available agents")
                        .foregroundStyle(.secondary)
                    Text("All agents from connected gateways are already in the sidebar.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(availableAgents.indices, id: \.self) { index in
                            let (gateway, agent) = availableAgents[index]
                            Button {
                                let binding = AgentBinding(
                                    gatewayId: gateway.id,
                                    agentId: agent.id,
                                    localDisplayName: agent.name,
                                    railOrder: gatewayManager.sortedAgentBindings.count + 1
                                )
                                gatewayManager.addAgentBinding(binding)
                                onAddBinding(binding)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(agent.name ?? agent.id.capitalized)
                                            .font(.body)
                                        Text(gateway.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()

            Button {
                onConnectNewGateway()
            } label: {
                HStack {
                    Image(systemName: "server.rack")
                    Text("Connect New Gateway…")
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 280)
    }
}