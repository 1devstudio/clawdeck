import SwiftUI
import AppKit

struct AgentSettingsSheet: View {
    let appViewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var host: String = ""
    @State private var port: String = "443"
    @State private var useTLS: Bool = true
    @State private var token: String = ""
    @State private var selectedAvatar: String? = "sf:robot"
    @State private var customAvatarData: Data?
    @State private var isConnecting = false
    @State private var errorMessage: String?

    /// Built-in SF Symbol avatars.
    private let builtInAvatars = [
        "robot", "desktopcomputer", "brain.head.profile", "cpu",
        "cloud", "server.rack", "antenna.radiowaves.left.and.right",
        "globe", "bolt.circle", "wand.and.stars", "sparkles",
        "terminal", "chevron.left.forwardslash.chevron.right",
        "gearshape", "atom"
    ]

    /// The profile being edited (nil = creating new).
    private var editingProfile: ConnectionProfile? {
        guard let id = appViewModel.editingAgentProfileId else { return nil }
        return appViewModel.connectionManager.profiles.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text(editingProfile != nil ? "Edit Agent" : "New Agent")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Avatar section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Avatar")
                            .font(.headline)

                        // Current avatar preview + name
                        HStack(spacing: 16) {
                            // Large preview
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: 64, height: 64)

                                if let customData = customAvatarData, let nsImage = NSImage(data: customData) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                } else if let avatar = selectedAvatar, avatar.hasPrefix("sf:") {
                                    Image(systemName: String(avatar.dropFirst(3)))
                                        .font(.system(size: 28))
                                        .foregroundStyle(Color.accentColor)
                                } else {
                                    Text(initials(for: displayName))
                                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }

                            TextField("Agent Name", text: $displayName)
                                .textFieldStyle(.roundedBorder)
                                .font(.title3)
                        }

                        // Avatar grid
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 8), count: 8), spacing: 8) {
                            ForEach(builtInAvatars, id: \.self) { symbol in
                                let avatarKey = "sf:\(symbol)"
                                Button {
                                    selectedAvatar = avatarKey
                                    customAvatarData = nil
                                } label: {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(selectedAvatar == avatarKey ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: symbol)
                                            .font(.system(size: 18))
                                            .foregroundStyle(selectedAvatar == avatarKey ? Color.accentColor : Color.secondary)
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selectedAvatar == avatarKey ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            // Upload custom image button
                            Button {
                                pickCustomAvatar()
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(customAvatarData != nil ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 16))
                                        .foregroundStyle(customAvatarData != nil ? Color.accentColor : Color.secondary)
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(customAvatarData != nil ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Upload custom image")
                        }
                    }

                    Divider()

                    // Connection section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Connection")
                            .font(.headline)

                        LabeledContent("Host") {
                            TextField("hostname or IP", text: $host)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("Port") {
                            TextField("443", text: $port)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        Toggle("Use TLS (wss://)", isOn: $useTLS)
                        LabeledContent("Token") {
                            SecureField("Gateway token", text: $token)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            Divider()

            // Error + actions
            HStack {
                if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(editingProfile != nil ? "Save" : "Add & Connect") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(displayName.isEmpty || host.isEmpty || isConnecting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(width: 520, height: 580)
        .onAppear { loadFromProfile() }
    }

    private func loadFromProfile() {
        guard let profile = editingProfile else { return }
        displayName = profile.displayName
        host = profile.host
        port = String(profile.port)
        useTLS = profile.useTLS
        token = profile.token ?? ""
        selectedAvatar = profile.avatarName ?? "sf:robot"
        // TODO: load custom avatar data if avatarName is not sf: prefixed
    }

    private func save() async {
        isConnecting = true
        errorMessage = nil

        guard let portNumber = Int(port) else {
            errorMessage = "Invalid port number"
            isConnecting = false
            return
        }

        // Save custom avatar to disk if present
        var finalAvatarName = selectedAvatar
        if let customData = customAvatarData {
            let filename = "\(UUID().uuidString).png"
            if saveAvatarToDisk(data: customData, filename: filename) {
                finalAvatarName = filename
            }
        }

        if let existing = editingProfile {
            // Update existing
            var updated = existing
            updated.displayName = displayName
            updated.host = host
            updated.port = portNumber
            updated.useTLS = useTLS
            updated.token = token.isEmpty ? nil : token
            updated.avatarName = finalAvatarName
            appViewModel.connectionManager.updateProfile(updated)

            // Reconnect if this is the active profile
            if appViewModel.connectionManager.activeProfile?.id == existing.id {
                await appViewModel.switchAgent(updated)
            }
        } else {
            // Create new
            let profile = ConnectionProfile(
                name: displayName,
                displayName: displayName,
                host: host,
                port: portNumber,
                useTLS: useTLS,
                token: token.isEmpty ? nil : token,
                isDefault: appViewModel.connectionManager.profiles.isEmpty,
                avatarName: finalAvatarName
            )
            appViewModel.connectionManager.addProfile(profile)
            await appViewModel.switchAgent(profile)
        }

        isConnecting = false
        dismiss()
    }

    private func pickCustomAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose Avatar Image"
        panel.message = "Select a PNG or JPEG image for the agent avatar."

        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            // Resize to reasonable size (128x128 max)
            if let nsImage = NSImage(data: data) {
                let resized = resizeImage(nsImage, maxSize: 128)
                customAvatarData = resized.tiffRepresentation.flatMap {
                    NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
                }
                selectedAvatar = nil // Deselect SF symbols
            }
        }
    }

    private func resizeImage(_ image: NSImage, maxSize: CGFloat) -> NSImage {
        let size = image.size
        let scale = min(maxSize / size.width, maxSize / size.height, 1.0)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        return resized
    }

    private func saveAvatarToDisk(data: Data, filename: String) -> Bool {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return false }
        let avatarDir = appSupport.appendingPathComponent("clawdeck/avatars")
        try? FileManager.default.createDirectory(at: avatarDir, withIntermediateDirectories: true)
        let fileURL = avatarDir.appendingPathComponent(filename)
        return (try? data.write(to: fileURL)) != nil
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}