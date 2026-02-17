import SwiftUI
import AppKit
import HighlightSwift

/// Application preferences window.
struct SettingsView: View {
    let appViewModel: AppViewModel
    @State private var selectedTab: SettingsTab = .appearance

    enum SettingsTab: String, CaseIterable {
        case appearance = "Appearance"
        case theme = "Theme"
        case shortcuts = "Shortcuts"
        case advanced = "Advanced"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag(SettingsTab.appearance)

            ThemeSettingsView(appViewModel: appViewModel)
                .tabItem {
                    Label("Theme", systemImage: "paintpalette")
                }
                .tag(SettingsTab.theme)

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
        .frame(width: 520, height: 580)
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @AppStorage("messageTextSize") private var messageTextSize: Double = 14
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage("codeHighlightTheme") private var codeHighlightThemeRaw: String = HighlightTheme.github.rawValue

    @AppStorage("bgMode") private var bgModeRaw: String = InnerPanelBackgroundMode.none.rawValue
    @AppStorage("bgSolidColorHex") private var bgSolidColorHex: String = "#1E1E2E"
    @AppStorage("bgUnsplashURL") private var bgUnsplashURL: String = ""
    @AppStorage("bgUnsplashPhotographer") private var bgUnsplashPhotographer: String = ""

    @State private var solidColor: Color = .init(hex: "#1E1E2E")
    @State private var showUnsplashPicker = false

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
            Section("Background") {
                Picker("Style", selection: bgMode) {
                    ForEach(InnerPanelBackgroundMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if bgModeRaw == InnerPanelBackgroundMode.none.rawValue {
                    // No extra controls needed
                } else if bgModeRaw == InnerPanelBackgroundMode.solidColor.rawValue {
                    ColorPicker("Color", selection: $solidColor, supportsOpacity: false)
                        .onChange(of: solidColor) { _, newColor in
                            bgSolidColorHex = hexFromColor(newColor)
                        }
                } else {
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
            }

            Section("Messages") {
                Slider(value: $messageTextSize, in: 12...20, step: 1) {
                    Text("Text Size: \(Int(messageTextSize))pt")
                }
            }

            Section("Theme") {
                Picker("Appearance", selection: appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Picker("Code Highlight", selection: codeHighlightTheme) {
                    ForEach(HighlightTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            solidColor = Color(hex: bgSolidColorHex)
        }
        .sheet(isPresented: $showUnsplashPicker) {
            UnsplashPickerSheet()
        }
    }

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
