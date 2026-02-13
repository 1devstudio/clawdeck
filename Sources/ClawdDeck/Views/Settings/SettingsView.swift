import SwiftUI

/// Application preferences window.
struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .connections

    /// Shared app view model — injected from the environment.
    var appViewModel: AppViewModel?

    enum SettingsTab: String, CaseIterable {
        case connections = "Connections"
        case gateway = "Gateway"
        case appearance = "Appearance"
        case shortcuts = "Shortcuts"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ConnectionSettingsView()
                .tabItem {
                    Label("Connections", systemImage: "network")
                }
                .tag(SettingsTab.connections)

            GatewaySettingsView(connectionManager: appViewModel?.connectionManager)
                .tabItem {
                    Label("Gateway", systemImage: "gearshape.2")
                }
                .tag(SettingsTab.gateway)

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
        .frame(width: 700, height: 550)
    }
}

// MARK: - Connection Settings

struct ConnectionSettingsView: View {
    @State private var profiles = ConnectionProfile.loadAll()
    @State private var selectedProfileId: String?

    var body: some View {
        HSplitView {
            // Profile list
            List(profiles, selection: $selectedProfileId) { profile in
                VStack(alignment: .leading) {
                    Text(profile.name)
                        .fontWeight(.medium)
                    Text(profile.displayAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(profile.id)
            }
            .frame(minWidth: 150)
            .toolbar {
                ToolbarItem {
                    Button {
                        let newProfile = ConnectionProfile(
                            name: "New Connection",
                            isDefault: profiles.isEmpty
                        )
                        profiles.append(newProfile)
                        selectedProfileId = newProfile.id
                        ConnectionProfile.saveAll(profiles)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }

            // Profile detail
            if let id = selectedProfileId,
               let index = profiles.firstIndex(where: { $0.id == id }) {
                Form {
                    TextField("Name", text: $profiles[index].name)
                    TextField("Host", text: $profiles[index].host)
                    TextField("Port", value: $profiles[index].port, format: .number)
                    Toggle("Use TLS", isOn: $profiles[index].useTLS)
                    Toggle("Default", isOn: $profiles[index].isDefault)
                }
                .formStyle(.grouped)
                .onChange(of: profiles) { _, newValue in
                    ConnectionProfile.saveAll(newValue)
                }
            } else {
                ContentUnavailableView(
                    "No Profile Selected",
                    systemImage: "network",
                    description: Text("Select or create a connection profile.")
                )
            }
        }
        .padding()
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
