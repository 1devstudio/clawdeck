import SwiftUI

/// TODO: This view needs to be updated to work with the new agent binding architecture.
/// For now it shows a placeholder message.
struct AgentSettingsSheet: View {
    let appViewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Agent Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This feature needs to be updated for the new two-layer architecture.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(width: 400, height: 300)
    }

}