import SwiftUI

/// A single session item in the sidebar.
struct SessionRow: View {
    let session: Session
    let isStarred: Bool
    let isRenaming: Bool
    @Binding var renameText: String
    var onCommitRename: () -> Void
    var onCancelRename: () -> Void
    var onDoubleClickTitle: () -> Void
    @Environment(\.messageTextSize) private var messageTextSize
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isRenaming {
                TextField("Session name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: messageTextSize))
                    .fontWeight(.medium)
                    .focused($isTextFieldFocused)
                    .onSubmit { onCommitRename() }
                    .onExitCommand { onCancelRename() }
                    .onAppear { isTextFieldFocused = true }
            } else {
                HStack(spacing: 4) {
                    if isStarred {
                        Image(systemName: "star.fill")
                            .font(.system(size: messageTextSize - 3))
                            .foregroundStyle(.yellow)
                    }
                    Text(session.displayTitle)
                        .font(.system(size: messageTextSize))
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .onTapGesture(count: 2) {
                    onDoubleClickTitle()
                }
            }

            if let lastMessage = session.lastMessage, !lastMessage.isEmpty {
                Text(lastMessage)
                    .font(.system(size: messageTextSize - 2))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            if let date = session.lastMessageAt ?? session.updatedAt as Date? {
                Text(date, style: .relative)
                    .font(.system(size: messageTextSize - 3))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
