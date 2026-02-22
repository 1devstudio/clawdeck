import SwiftUI
import AppKit
import HighlightSwift
import Sparkle

/// Ensures the SPM executable is treated as a regular GUI app with proper
/// keyboard event routing, menu bar, and dock presence.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Tracks which windows have already been configured to avoid redundant work.
    private var configuredWindowNumbers: Set<Int> = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set the app icon (SPM executables don't pick it up from the asset catalog automatically)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }

        // Make the title bar transparent so content flows under the traffic lights
        if let window = NSApp.windows.first {
            Self.configureWindowTitleBar(window)
            configuredWindowNumbers.insert(window.windowNumber)
        }

        // Re-apply toolbar config whenever a new window becomes key (handles reopen after close)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard !configuredWindowNumbers.contains(window.windowNumber) else { return }
        // Only configure main WindowGroup windows (unified toolbar sets fullSizeContentView).
        // Settings and Log windows use standard .titleBar and don't need customization.
        guard window.styleMask.contains(.fullSizeContentView),
              window.toolbar != nil else { return }

        configuredWindowNumbers.insert(window.windowNumber)
        Self.configureWindowTitleBar(window)
    }

    /// Configure the window for a Slack-style layout where content extends into the title bar.
    static func configureWindowTitleBar(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Extend content into the title bar area
        window.styleMask.insert(.fullSizeContentView)
        // Prevent macOS from treating transparent areas as window drag handles,
        // which blocks SwiftUI button/gesture taps in the agent rail.
        window.isMovableByWindowBackground = false
        // Match the toolbar/title bar background to the agent rail
        window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)

        // Remove toolbar container background/border by making items borderless
        if let toolbar = window.toolbar {
            toolbar.displayMode = .iconOnly
            // Walk the toolbar items and remove background separators
            if #available(macOS 15.0, *) {
                toolbar.allowsDisplayModeCustomization = false
            }
        }

        // Remove the toolbar border line between title bar and content
        window.titlebarSeparatorStyle = .none

        // Strip bordered style from all toolbar items
        if let toolbar = window.toolbar {
            for item in toolbar.items {
                item.isBordered = false
            }
        }

        // Also strip backgrounds from toolbar item viewer NSViews
        // (delayed because SwiftUI toolbar views are created asynchronously)
        for delay in [0.1, 0.3, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // Re-strip toolbar items (SwiftUI may recreate them)
                if let toolbar = window.toolbar {
                    for item in toolbar.items {
                        item.isBordered = false
                    }
                }
                // Walk only titlebar views — skip the content view (NSHostingView)
                // to avoid modifying SwiftUI-managed views which breaks event delivery.
                if let themeFrame = window.contentView?.superview {
                    for subview in themeFrame.subviews where subview !== window.contentView {
                        stripToolbarContainerBackgrounds(in: subview)
                    }
                }
            }
        }
    }

    /// Recursively find toolbar-related views and remove their backgrounds.
    private static func stripToolbarContainerBackgrounds(in view: NSView?) {
        guard let view = view else { return }
        let className = String(describing: type(of: view))

        if className.contains("ToolbarItemViewer") ||
           className.contains("ToolbarItemGroupViewer") ||
           className.contains("NSToolbarView") ||
           className.contains("ToolbarClipView") {
            view.wantsLayer = true
            view.layer?.backgroundColor = .clear
            view.layer?.borderWidth = 0
            view.layer?.borderColor = .clear
            if let cell = (view as? NSControl)?.cell {
                cell.isBordered = false
            }
        }

        for subview in view.subviews {
            stripToolbarContainerBackgrounds(in: subview)
        }
    }
}

/// Clawd Deck — native macOS desktop app for Clawdbot.
@main
struct ClawdDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appViewModel = AppViewModel()
    @State private var softwareUpdate = SoftwareUpdateViewModel()
    @Environment(\.openWindow) private var openWindow
    @AppStorage("messageTextSize") private var messageTextSize: Double = 14
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage("codeHighlightTheme") private var codeHighlightThemeRaw: String = HighlightTheme.github.rawValue

    @AppStorage("bgMode") private var bgModeRaw: String = InnerPanelBackgroundMode.none.rawValue
    @AppStorage("bgSolidColorHex") private var bgSolidColorHex: String = "#1E1E2E"
    @AppStorage("bgUnsplashURL") private var bgUnsplashURL: String = ""
    @AppStorage("bgUnsplashPhotographer") private var bgUnsplashPhotographer: String = ""

    /// Tracks the OS dark-mode setting so we can resolve "System" mode to an
    /// explicit scheme. Updated via distributed notification when the user
    /// changes macOS appearance in System Settings.
    @State private var osIsDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"

    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    /// Always returns a concrete scheme — never nil — so that
    /// `.preferredColorScheme()` immediately updates the window appearance.
    private var resolvedColorScheme: ColorScheme {
        switch appearanceMode {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return osIsDark ? .dark : .light
        }
    }

    private var codeHighlightTheme: HighlightTheme {
        HighlightTheme(rawValue: codeHighlightThemeRaw) ?? .github
    }

    private var innerPanelBackgroundConfig: InnerPanelBackgroundConfig {
        InnerPanelBackgroundConfig(
            mode: InnerPanelBackgroundMode(rawValue: bgModeRaw) ?? .none,
            colorHex: bgSolidColorHex,
            unsplashURL: bgUnsplashURL,
            unsplashPhotographer: bgUnsplashPhotographer
        )
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainView(appViewModel: appViewModel)
                    .frame(minWidth: 800, minHeight: 500)

                if appViewModel.showConnectionSetup {
                    Color(nsColor: .windowBackgroundColor)
                        .ignoresSafeArea()
                    ConnectionSetupView(appViewModel: appViewModel)
                }
            }
            .environment(\.messageTextSize, messageTextSize)
            .environment(\.codeHighlightTheme, codeHighlightTheme)
            .environment(\.innerPanelBackground, innerPanelBackgroundConfig)
            .preferredColorScheme(resolvedColorScheme)
            .onReceive(DistributedNotificationCenter.default().publisher(for: .init("AppleInterfaceThemeChangedNotification"))) { _ in
                osIsDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
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
            // MARK: - App Menu / Check for Updates

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    softwareUpdate.checkForUpdates()
                }
                .disabled(!softwareUpdate.canCheckForUpdates)
            }

            TextEditingCommands()

            // MARK: - File / New Item

            CommandGroup(after: .newItem) {
                Button("New Session") {
                    Task { await appViewModel.createNewSession() }
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Session in New Window") {
                    Task { await appViewModel.createNewSession() }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Close Session") {
                    appViewModel.closeCurrentSession()
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(appViewModel.selectedSessionKey == nil)
            }

            // MARK: - View / Sidebar

            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    appViewModel.toggleSidebar()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Toggle Inspector") {
                    appViewModel.isInspectorVisible.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Divider()

                Button("Application Log") {
                    openWindow(id: "application-log")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button("Quick Open") {
                    appViewModel.focusSearchBar()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Focus Composer") {
                    appViewModel.focusComposer()
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(appViewModel.selectedSessionKey == nil)

                Divider()

                Button("Previous Session") {
                    appViewModel.selectPreviousSession()
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(appViewModel.sidebarViewModel.filteredSessions.isEmpty)

                Button("Next Session") {
                    appViewModel.selectNextSession()
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(appViewModel.sidebarViewModel.filteredSessions.isEmpty)
            }

            // MARK: - Agent Switching (⌘1-9)

            CommandMenu("Agents") {
                ForEach(Array(appViewModel.gatewayManager.sortedAgentBindings.prefix(9).enumerated()), id: \.offset) { index, binding in
                    Button("Switch to \(binding.displayName(from: appViewModel.gatewayManager))") {
                        appViewModel.switchToAgent(at: index + 1)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView(appViewModel: appViewModel)
                .environment(\.messageTextSize, messageTextSize)
                .environment(\.codeHighlightTheme, codeHighlightTheme)
                .environment(\.innerPanelBackground, innerPanelBackgroundConfig)
                .environment(\.themeConfig, appViewModel.themeConfig)
        }
        
        Window("Application Log", id: "application-log") {
            LogView()
                .environment(\.messageTextSize, messageTextSize)
                .environment(\.codeHighlightTheme, codeHighlightTheme)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 600)
    }
}
