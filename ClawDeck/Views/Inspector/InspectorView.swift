import SwiftUI

/// Right panel showing details about the selected session.
struct InspectorView: View {
    let session: Session
    let appViewModel: AppViewModel

    var body: some View {
        SessionInfoContent(
            session: session,
            appViewModel: appViewModel
        )
    }
}

// MARK: - Session Info Content

/// The session info content.
struct SessionInfoContent: View {
    let session: Session
    let appViewModel: AppViewModel

    @State private var editingLabel = false
    @State private var labelText = ""
    @FocusState private var isLabelFieldFocused: Bool

    var body: some View {
        Form {
            Section("Session Info") {
                if editingLabel {
                    LabeledContent("Title") {
                        TextField("Session name", text: $labelText)
                            .textFieldStyle(.roundedBorder)
                            .focused($isLabelFieldFocused)
                            .onSubmit { commitLabel() }
                            .onExitCommand { editingLabel = false }
                    }
                } else {
                    LabeledContent("Title") {
                        HStack {
                            Text(session.displayTitle)
                                .lineLimit(2)
                            Spacer()
                            Button {
                                labelText = session.label ?? session.displayTitle
                                editingLabel = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    isLabelFieldFocused = true
                                }
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                LabeledContent("Starred") {
                    Button {
                        appViewModel.starredSessionsStore.toggle(session.key)
                    } label: {
                        Image(systemName: appViewModel.starredSessionsStore.isStarred(session.key)
                              ? "star.fill" : "star")
                            .foregroundStyle(appViewModel.starredSessionsStore.isStarred(session.key)
                                             ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
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

                if let total = session.totalTokens, total > 0 {
                    let contextTokens = session.contextTokens ?? appViewModel.defaultContextTokens
                    if let ctx = contextTokens, ctx > 0 {
                        let pct = min(100, Int(round(Double(total) / Double(ctx) * 100)))
                        LabeledContent("Context usage") {
                            Text("\(formatTokenCount(total)) / \(formatTokenCount(ctx)) (\(pct)%)")
                                .monospacedDigit()
                        }
                    } else {
                        LabeledContent("Total tokens", value: formatTokenCount(total))
                    }
                }
            }

            Section {
                Button("Delete Session", role: .destructive) {
                    Task {
                        await appViewModel.deleteSession(session.key)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            let m = Double(count) / 1_000_000
            return m >= 10 ? String(format: "%.0fM", m) : String(format: "%.1fM", m)
        } else if count >= 1000 {
            return String(format: "%.0fk", Double(count) / 1000)
        }
        return "\(count)"
    }

    private func commitLabel() {
        editingLabel = false
        guard !labelText.isEmpty else { return }
        Task {
            await appViewModel.renameSession(session.key, label: labelText)
        }
    }
}
