import SwiftUI

/// A single agent item in the sidebar.
struct AgentRow: View {
    let agent: Agent
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        HStack(spacing: 10) {
            // Avatar
            ZStack {
                Circle()
                    .fill(agent.isOnline ? themeColor.opacity(0.15) : Color.gray.opacity(0.1))
                    .frame(width: 32, height: 32)

                if let avatarURL = agent.avatarURL {
                    AsyncImage(url: avatarURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        agentInitial
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                } else {
                    agentInitial
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(agent.isOnline ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2)
                    )
            }

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(agent.isOnline ? "Online" : "Offline")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var agentInitial: some View {
        Text(String(agent.name.prefix(1)).uppercased())
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(agent.isOnline ? themeColor : Color.secondary)
    }
}
