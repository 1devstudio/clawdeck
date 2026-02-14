import SwiftUI
import AppKit

/// Ensures the SPM executable is treated as a regular GUI app with proper
/// keyboard event routing, menu bar, and dock presence.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make the title bar transparent so content flows under the traffic lights
        if let window = NSApp.windows.first {
            configureWindowTitleBar(window)
        }
    }

    /// Configure the window for a Slack-style layout where content extends into the title bar.
    static func configureWindowTitleBar(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        // Extend content into the title bar area
        window.styleMask.insert(.fullSizeContentView)
    }
}

/// Clawd Deck — native macOS desktop app for Clawdbot.
@main
struct ClawdDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if appViewModel.showConnectionSetup {
                    ConnectionSetupView(appViewModel: appViewModel)
                } else {
                    MainView(appViewModel: appViewModel)
                        .frame(minWidth: 800, minHeight: 500)
                }
            }
            .task {
                if appViewModel.hasProfiles {
                    await appViewModel.connectAndLoad()
                }
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1100, height: 700)
        .commands {
            TextEditingCommands()

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
