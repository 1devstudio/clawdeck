import SwiftUI

/// Non-dismissible banner shown when the gateway connection is lost or reconnecting.
struct ConnectionBanner: View {
    let state: ConnectionState
    let onReconnect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if state == .reconnecting || state == .connecting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(subtitleText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if state == .disconnected {
                Button("Reconnect") {
                    onReconnect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var titleText: String {
        switch state {
        case .reconnecting, .connecting:
            "Connection lost. Reconnecting..."
        case .disconnected:
            "Connection lost"
        default:
            ""
        }
    }

    private var subtitleText: String {
        switch state {
        case .reconnecting, .connecting:
            "Messages will resume when reconnected"
        case .disconnected:
            "Unable to reconnect automatically"
        default:
            ""
        }
    }
}
