import SwiftUI

/// Application preferences window.
struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .appearance

    enum SettingsTab: String, CaseIterable {
        case appearance = "Appearance"
        case shortcuts = "Shortcuts"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag(SettingsTab.appearance)

            ShortcutSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .tag(SettingsTab.shortcuts)
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - Appearance Settings (placeholder)

struct AppearanceSettingsView: View {
    @AppStorage("messageTextSize") private var messageTextSize: Double = 14

    var body: some View {
        Form {
            Section("Messages") {
                Slider(value: $messageTextSize, in: 12...20, step: 1) {
                    Text("Text Size: \(Int(messageTextSize))pt")
                }
            }

            Section("Theme") {
                Text("Follow system appearance")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Shortcut Settings (placeholder)

struct ShortcutSettingsView: View {
    var body: some View {
        Form {
            Section("Navigation") {
                LabeledContent("Quick Open", value: "⌘K")
                LabeledContent("New Session", value: "⌘N")
                LabeledContent("Toggle Sidebar", value: "⌘⇧S")
                LabeledContent("Toggle Inspector", value: "⌘⇧I")
            }

            Section("Chat") {
                LabeledContent("Send Message", value: "⌘↩")
                LabeledContent("Stop Generation", value: "Esc")
                LabeledContent("Focus Composer", value: "⌘L")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
