import SwiftUI

/// A single session item in the sidebar.
struct SessionRow: View {
    let session: Session
    let isRenaming: Bool
    @Binding var renameText: String
    var onCommitRename: () -> Void
    var onCancelRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isRenaming {
                TextField("Session name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .fontWeight(.medium)
                    .onSubmit { onCommitRename() }
                    .onExitCommand { onCancelRename() }
            } else {
                Text(session.displayTitle)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if let lastMessage = session.lastMessage, !lastMessage.isEmpty {
                Text(lastMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            if let date = session.lastMessageAt ?? session.updatedAt as Date? {
                Text(date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
