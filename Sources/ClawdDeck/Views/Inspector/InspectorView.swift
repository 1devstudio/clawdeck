import SwiftUI

/// Right panel showing details about the selected session.
struct InspectorView: View {
    let session: Session
    let appViewModel: AppViewModel

    @State private var editingLabel = false
    @State private var labelText = ""

    var body: some View {
        Form {
            Section("Session Info") {
                LabeledContent("Title") {
                    if editingLabel {
                        TextField("Session title", text: $labelText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { commitLabel() }
                    } else {
                        HStack {
                            Text(session.displayTitle)
                                .lineLimit(2)
                            Spacer()
                            Button {
                                labelText = session.label ?? session.displayTitle
                                editingLabel = true
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                LabeledContent("Key", value: session.key)

                if let model = session.model {
                    LabeledContent("Model", value: model)
                }

                if let agentId = session.agentId {
                    LabeledContent("Agent") {
                        let agent = appViewModel.agents.first { $0.id == agentId }
                        Text(agent?.name ?? agentId)
                    }
                }

                LabeledContent("Updated") {
                    Text(session.updatedAt, style: .date)
                    Text(session.updatedAt, style: .time)
                }
            }

            Section("Statistics") {
                let messages = appViewModel.messageStore.messages(for: session.key)
                LabeledContent("Messages", value: "\(messages.count)")
                LabeledContent("User messages", value: "\(messages.filter { $0.role == .user }.count)")
                LabeledContent("Assistant messages", value: "\(messages.filter { $0.role == .assistant }.count)")
            }

            Section {
                Button("Delete Session", role: .destructive) {
                    Task {
                        await appViewModel.deleteSession(session.key)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func commitLabel() {
        editingLabel = false
        guard !labelText.isEmpty else { return }
        Task {
            await appViewModel.renameSession(session.key, label: labelText)
        }
    }
}
