import SwiftUI
import AppKit
import HighlightSwift

/// Application preferences window.
struct SettingsView: View {
    let appViewModel: AppViewModel
    @State private var selectedTab: SettingsTab = .appearance

    enum SettingsTab: String, CaseIterable {
        case appearance = "Appearance"
        case shortcuts = "Shortcuts"
        case advanced = "Advanced"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            AppearanceSettingsView(appViewModel: appViewModel)
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag(SettingsTab.appearance)

            ShortcutSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .tag(SettingsTab.shortcuts)

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                .tag(SettingsTab.advanced)
        }
        .frame(width: 520, height: 620)
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    let appViewModel: AppViewModel

    // ── AppStorage (general + background) ────────────────────────────
    @AppStorage("messageTextSize") private var messageTextSize: Double = 14
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage("codeHighlightTheme") private var codeHighlightThemeRaw: String = HighlightTheme.github.rawValue

    @AppStorage("bgMode") private var bgModeRaw: String = InnerPanelBackgroundMode.none.rawValue
    @AppStorage("bgSolidColorHex") private var bgSolidColorHex: String = "#1E1E2E"
    @AppStorage("bgUnsplashURL") private var bgUnsplashURL: String = ""
    @AppStorage("bgUnsplashPhotographer") private var bgUnsplashPhotographer: String = ""

    @State private var solidColor: Color = .init(hex: "#1E1E2E")
    @State private var showUnsplashPicker = false

    // ── Theme colors (local editing copies) ──────────────────────────
    @State private var userBubbleColor: Color = .blue
    @State private var assistantBubbleColor: Color = .gray
    @State private var systemBubbleColor: Color = .yellow
    @State private var sidebarColor: Color = .gray
    @State private var composerColor: Color = .gray
    @State private var composerFieldColor: Color = .gray
    @State private var composerFieldBorderColor: Color = .gray
    @State private var toolsPanelColor: Color = .gray
    @State private var toolBlockColor: Color = .gray
    @State private var chromeColor: Color = .gray

    // ── Theme style pickers ──────────────────────────────────────────
    @State private var bubbleStyle: SurfaceStyle = .glass
    @State private var sidebarStyle: SurfaceStyle = .glass
    @State private var composerStyle: SurfaceStyle = .glass
    @State private var toolsPanelStyle: SurfaceStyle = .glass

    // ── Bindings for AppStorage enums ────────────────────────────────

    private var appearanceMode: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    private var codeHighlightTheme: Binding<HighlightTheme> {
        Binding(
            get: { HighlightTheme(rawValue: codeHighlightThemeRaw) ?? .github },
            set: { codeHighlightThemeRaw = $0.rawValue }
        )
    }

    private var bgMode: Binding<InnerPanelBackgroundMode> {
        Binding(
            get: { InnerPanelBackgroundMode(rawValue: bgModeRaw) ?? .none },
            set: { bgModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            // ── General ──────────────────────────────────────────────
            Section {
                Picker("Appearance", selection: appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Slider(value: $messageTextSize, in: 12...20, step: 1) {
                    Text("Text Size: \(Int(messageTextSize))pt")
                }

                Picker("Code Highlight", selection: codeHighlightTheme) {
                    ForEach(HighlightTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
            } header: {
                Label("General", systemImage: "textformat.size")
            }

            // ── Chat Background ──────────────────────────────────────
            Section {
                Picker("Style", selection: bgMode) {
                    ForEach(InnerPanelBackgroundMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if bgModeRaw == InnerPanelBackgroundMode.solidColor.rawValue {
                    ColorPicker("Color", selection: $solidColor, supportsOpacity: false)
                        .onChange(of: solidColor) { _, newColor in
                            bgSolidColorHex = hexFromColor(newColor)
                        }
                } else if bgModeRaw == InnerPanelBackgroundMode.unsplash.rawValue {
                    HStack {
                        if !bgUnsplashURL.isEmpty {
                            AsyncImage(url: URL(string: bgUnsplashURL)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 60, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                            Text("by \(bgUnsplashPhotographer)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Choose Image…") {
                            showUnsplashPicker = true
                        }
                    }
                }
            } header: {
                Label("Chat Background", systemImage: "photo")
            }

            // ── Chat Bubbles ─────────────────────────────────────────
            Section {
                Picker("Surface Style", selection: $bubbleStyle) {
                    ForEach(SurfaceStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                ColorPicker("User Bubble", selection: $userBubbleColor, supportsOpacity: false)
                ColorPicker("Assistant Bubble", selection: $assistantBubbleColor, supportsOpacity: false)
                ColorPicker("System Bubble", selection: $systemBubbleColor, supportsOpacity: false)
            } header: {
                Label("Chat Bubbles", systemImage: "bubble.left.and.bubble.right")
            }

            // ── Sidebar ──────────────────────────────────────────────
            Section {
                Picker("Surface Style", selection: $sidebarStyle) {
                    ForEach(SurfaceStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                if sidebarStyle != .glass {
                    ColorPicker("Background", selection: $sidebarColor, supportsOpacity: false)
                }
            } header: {
                Label("Sidebar", systemImage: "sidebar.left")
            }

            // ── Composer ─────────────────────────────────────────────
            Section {
                Picker("Surface Style", selection: $composerStyle) {
                    ForEach(SurfaceStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                if composerStyle != .glass {
                    ColorPicker("Background", selection: $composerColor, supportsOpacity: false)
                }
                ColorPicker("Field Background", selection: $composerFieldColor, supportsOpacity: false)
                ColorPicker("Field Border", selection: $composerFieldBorderColor, supportsOpacity: false)
            } header: {
                Label("Composer", systemImage: "pencil.line")
            }

            // ── Tools Panel ──────────────────────────────────────────
            Section {
                Picker("Surface Style", selection: $toolsPanelStyle) {
                    ForEach(SurfaceStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                if toolsPanelStyle != .glass {
                    ColorPicker("Panel Background", selection: $toolsPanelColor, supportsOpacity: false)
                    ColorPicker("Tool Blocks", selection: $toolBlockColor, supportsOpacity: false)
                }
            } header: {
                Label("Tools Panel", systemImage: "wrench.and.screwdriver")
            }

            // ── Chrome ───────────────────────────────────────────────
            Section {
                ColorPicker("Background", selection: $chromeColor, supportsOpacity: false)
            } header: {
                Label("Chrome", systemImage: "macwindow")
            }

            // ── Reset ────────────────────────────────────────────────
            Section {
                Button("Reset Theme to Defaults") {
                    let defaults = ThemeConfig.default
                    loadThemeColors(from: defaults)
                    applyTheme(defaults)
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            solidColor = Color(hex: bgSolidColorHex)
            loadThemeColors(from: appViewModel.themeConfig)
        }
        .sheet(isPresented: $showUnsplashPicker) {
            UnsplashPickerSheet()
        }
        // Live theme sync
        .onChange(of: bubbleStyle) { _, _ in syncTheme() }
        .onChange(of: userBubbleColor) { _, _ in syncTheme() }
        .onChange(of: assistantBubbleColor) { _, _ in syncTheme() }
        .onChange(of: systemBubbleColor) { _, _ in syncTheme() }
        .onChange(of: sidebarStyle) { _, _ in syncTheme() }
        .onChange(of: sidebarColor) { _, _ in syncTheme() }
        .onChange(of: composerStyle) { _, _ in syncTheme() }
        .onChange(of: composerColor) { _, _ in syncTheme() }
        .onChange(of: composerFieldColor) { _, _ in syncTheme() }
        .onChange(of: composerFieldBorderColor) { _, _ in syncTheme() }
        .onChange(of: toolsPanelStyle) { _, _ in syncTheme() }
        .onChange(of: toolsPanelColor) { _, _ in syncTheme() }
        .onChange(of: toolBlockColor) { _, _ in syncTheme() }
        .onChange(of: chromeColor) { _, _ in syncTheme() }
    }

    // MARK: - Theme Sync

    private func loadThemeColors(from config: ThemeConfig) {
        bubbleStyle = config.bubbleStyle
        userBubbleColor = Color(hex: config.userBubbleColorHex)
        assistantBubbleColor = Color(hex: config.assistantBubbleColorHex)
        systemBubbleColor = Color(hex: config.systemBubbleColorHex)
        sidebarStyle = config.sidebarStyle
        sidebarColor = Color(hex: config.sidebarColorHex)
        composerStyle = config.composerStyle
        composerColor = Color(hex: config.composerColorHex)
        composerFieldColor = Color(hex: config.composerFieldColorHex)
        composerFieldBorderColor = Color(hex: config.composerFieldBorderColorHex)
        toolsPanelStyle = config.toolsPanelStyle
        toolsPanelColor = Color(hex: config.toolsPanelColorHex)
        toolBlockColor = Color(hex: config.toolBlockColorHex)
        chromeColor = Color(hex: config.chromeColorHex)
    }

    private func syncTheme() {
        var config = ThemeConfig()
        config.bubbleStyle = bubbleStyle
        config.userBubbleColorHex = hexFromColor(userBubbleColor)
        config.assistantBubbleColorHex = hexFromColor(assistantBubbleColor)
        config.systemBubbleColorHex = hexFromColor(systemBubbleColor)
        config.sidebarStyle = sidebarStyle
        config.sidebarColorHex = hexFromColor(sidebarColor)
        config.composerStyle = composerStyle
        config.composerColorHex = hexFromColor(composerColor)
        config.composerFieldColorHex = hexFromColor(composerFieldColor)
        config.composerFieldBorderColorHex = hexFromColor(composerFieldBorderColor)
        config.toolsPanelStyle = toolsPanelStyle
        config.toolsPanelColorHex = hexFromColor(toolsPanelColor)
        config.toolBlockColorHex = hexFromColor(toolBlockColor)
        config.chromeColorHex = hexFromColor(chromeColor)
        applyTheme(config)
    }

    private func applyTheme(_ config: ThemeConfig) {
        appViewModel.themeConfig = config
        appViewModel.saveThemeConfig()
    }

    // MARK: - Helpers

    private func hexFromColor(_ color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - Shortcut Settings

struct ShortcutSettingsView: View {
    var body: some View {
        Form {
            Section("Navigation") {
                LabeledContent("Quick Open", value: "⌘K")
                LabeledContent("New Session", value: "⌘N")
                LabeledContent("Duplicate Session", value: "⌘⇧N")
                LabeledContent("Close Session", value: "⌘W")
                LabeledContent("Toggle Sidebar", value: "⌘⇧S")
                LabeledContent("Toggle Inspector", value: "⌘⇧I")
                LabeledContent("Application Log", value: "⌘⇧L")
            }

            Section("Chat") {
                LabeledContent("Send Message", value: "↩")
                LabeledContent("New Line", value: "⇧↩")
                LabeledContent("Stop Generation", value: "Esc")
                LabeledContent("Focus Composer", value: "⌘L")
            }

            Section("Session Navigation") {
                LabeledContent("Previous Session", value: "⌘↑")
                LabeledContent("Next Session", value: "⌘↓")
            }

            Section("Agent Switching") {
                LabeledContent("Switch to Agent 1–9", value: "⌘1 – ⌘9")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @AppStorage("logLevel") private var logLevelRaw: String = AppLogLevel.info.rawValue
    
    private var logLevel: Binding<AppLogLevel> {
        Binding(
            get: { AppLogLevel(rawValue: logLevelRaw) ?? .info },
            set: { logLevelRaw = $0.rawValue }
        )
    }
    
    var body: some View {
        Form {
            Section("Logging") {
                Picker("Log Level", selection: logLevel) {
                    ForEach(AppLogLevel.allCases) { level in
                        HStack {
                            Image(systemName: level.sfSymbol)
                                .foregroundStyle(level.color)
                            Text(level.displayName)
                        }
                        .tag(level)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Log Level Descriptions:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("• Debug: All messages including detailed debugging information")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("• Info: General information messages and status updates")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("• Warning: Important messages that may indicate issues")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("• Error: Only critical errors and failures")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
