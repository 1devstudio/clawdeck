import SwiftUI

/// Settings tab for customizing UI theme: bubbles, sidebar, composer, tools panel, chrome.
struct ThemeSettingsView: View {
    let appViewModel: AppViewModel

    // Local editing copies of colors (Color type for ColorPicker)
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

    // Local style pickers
    @State private var bubbleStyle: SurfaceStyle = .glass
    @State private var sidebarStyle: SurfaceStyle = .glass
    @State private var composerStyle: SurfaceStyle = .glass
    @State private var toolsPanelStyle: SurfaceStyle = .glass

    var body: some View {
        Form {
            // ── 1. Chat Bubbles ──────────────────────────────────────
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

            // ── 2. Sidebar ──────────────────────────────────────────
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

            // ── 3. Composer ─────────────────────────────────────────
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

            // ── 4. Tools Panel ──────────────────────────────────────
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

            // ── 5. Chrome ───────────────────────────────────────────
            Section {
                ColorPicker("Background", selection: $chromeColor, supportsOpacity: false)
            } header: {
                Label("Chrome", systemImage: "macwindow")
            }

            // ── Reset ───────────────────────────────────────────────
            Section {
                Button("Reset to Defaults") {
                    let defaults = ThemeConfig.default
                    loadColors(from: defaults)
                    applyToViewModel(defaults)
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadColors(from: appViewModel.themeConfig)
        }
        // Apply changes live as colors/styles change
        .onChange(of: bubbleStyle) { _, _ in syncToViewModel() }
        .onChange(of: userBubbleColor) { _, _ in syncToViewModel() }
        .onChange(of: assistantBubbleColor) { _, _ in syncToViewModel() }
        .onChange(of: systemBubbleColor) { _, _ in syncToViewModel() }
        .onChange(of: sidebarStyle) { _, _ in syncToViewModel() }
        .onChange(of: sidebarColor) { _, _ in syncToViewModel() }
        .onChange(of: composerStyle) { _, _ in syncToViewModel() }
        .onChange(of: composerColor) { _, _ in syncToViewModel() }
        .onChange(of: composerFieldColor) { _, _ in syncToViewModel() }
        .onChange(of: composerFieldBorderColor) { _, _ in syncToViewModel() }
        .onChange(of: toolsPanelStyle) { _, _ in syncToViewModel() }
        .onChange(of: toolsPanelColor) { _, _ in syncToViewModel() }
        .onChange(of: toolBlockColor) { _, _ in syncToViewModel() }
        .onChange(of: chromeColor) { _, _ in syncToViewModel() }
    }

    // MARK: - Sync

    /// Load Color values from a ThemeConfig.
    private func loadColors(from config: ThemeConfig) {
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

    /// Build a ThemeConfig from the current local state and push it to the view model.
    private func syncToViewModel() {
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
        applyToViewModel(config)
    }

    private func applyToViewModel(_ config: ThemeConfig) {
        appViewModel.themeConfig = config
        appViewModel.saveThemeConfig()
    }

    // MARK: - Color conversion

    private func hexFromColor(_ color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
