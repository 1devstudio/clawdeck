import SwiftUI

/// Clawd Deck — native macOS desktop app for Clawdbot.
@main
struct ClawdDeckApp: App {
    @State private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            MainView(appViewModel: appViewModel)
                .frame(minWidth: 800, minHeight: 500)
                .task {
                    // Auto-connect on launch if a default profile exists
                    if appViewModel.hasProfiles {
                        await appViewModel.connectAndLoad()
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1100, height: 700)
        .commands {
            // Custom menu commands
            CommandGroup(after: .newItem) {
                Button("New Session") {
                    // TODO: Create new session via gateway
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    // Handled by NavigationSplitView
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Toggle Inspector") {
                    appViewModel.isInspectorVisible.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }
}
