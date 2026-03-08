import SwiftUI

/// Represents a channel with its status information for the UI.
struct ChannelInfo: Identifiable {
    let id: String              // channel key (e.g., "telegram")
    let label: String           // display name
    let detailLabel: String?    // description
    let systemImage: String     // SF Symbol name
    let configured: Bool
    let connected: Bool
    let enabled: Bool
    let loggedIn: Bool
    let error: String?
    let accounts: [ChannelAccountInfo]
    let supportsLogin: Bool
    let lastInboundAt: Date?
    let lastOutboundAt: Date?
}

struct ChannelAccountInfo: Identifiable {
    let accountId: String
    let configured: Bool
    let enabled: Bool
    let connected: Bool
    let loggedIn: Bool
    let error: String?
    let lastInboundAt: Date?
    let lastOutboundAt: Date?
    
    var id: String { accountId }
}

@Observable
@MainActor
final class ChannelsViewModel {
    private weak var appViewModel: AppViewModel?
    
    var channels: [ChannelInfo] = []
    var isLoading = false
    var errorMessage: String?
    var expandedChannelId: String?
    
    // QR Login state
    var loginChannelId: String?
    var qrCodeDataURL: String?
    var isLoginInProgress = false
    var loginStatusMessage: String?
    
    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
    }
    
    func loadChannels() async {
        guard let appViewModel = appViewModel,
              let client = appViewModel.activeClient else {
            errorMessage = "Not connected to gateway"
            return
        }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let payload = try await client.channelsStatus(probe: true)
            parseChannelStatus(payload)
        } catch {
            errorMessage = "Failed to load channels: \(error.localizedDescription)"
        }
    }
    
    func toggleExpanded(_ channelId: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedChannelId = (expandedChannelId == channelId) ? nil : channelId
        }
    }
    
    func logout(channel: String, accountId: String? = nil) async {
        guard let appViewModel = appViewModel,
              let client = appViewModel.activeClient else { return }
        do {
            try await client.channelsLogout(channel: channel, accountId: accountId)
            await loadChannels()
        } catch {
            errorMessage = "Logout failed: \(error.localizedDescription)"
        }
    }
    
    func startLogin(channel: String, accountId: String? = nil) async {
        guard let appViewModel = appViewModel,
              let client = appViewModel.activeClient else { return }
        loginChannelId = channel
        isLoginInProgress = true
        loginStatusMessage = "Initializing login…"
        qrCodeDataURL = nil
        
        do {
            let result = try await client.webLoginStart(force: true, accountId: accountId)
            if let dict = result.dictValue,
               let qr = dict["qrCode"] as? String {
                qrCodeDataURL = qr
                loginStatusMessage = "Scan the QR code with your phone"
                
                // Wait for login completion
                let waitResult = try await client.webLoginWait(accountId: accountId)
                if let waitDict = waitResult.dictValue,
                   let connected = waitDict["connected"] as? Bool, connected {
                    loginStatusMessage = "Connected successfully!"
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    cancelLogin()
                    await loadChannels()
                } else {
                    loginStatusMessage = "Login timed out. Try again."
                }
            } else {
                loginStatusMessage = "Failed to get QR code"
            }
        } catch {
            loginStatusMessage = "Login failed: \(error.localizedDescription)"
        }
        
        isLoginInProgress = false
    }
    
    func cancelLogin() {
        loginChannelId = nil
        qrCodeDataURL = nil
        isLoginInProgress = false
        loginStatusMessage = nil
    }
    
    // MARK: - Parsing
    
    private func parseChannelStatus(_ payload: AnyCodable) {
        guard let dict = payload.dictValue else { return }
        
        let channelOrder = dict["channelOrder"] as? [String] ?? []
        let channelLabels = dict["channelLabels"] as? [String: String] ?? [:]
        let channelDetailLabels = dict["channelDetailLabels"] as? [String: String] ?? [:]
        let channelSystemImages = dict["channelSystemImages"] as? [String: String] ?? [:]
        let channelsDict = dict["channels"] as? [String: Any] ?? [:]
        let accountsDict = dict["channelAccounts"] as? [String: Any] ?? [:]
        let channelMeta = dict["channelMeta"] as? [String: Any] ?? [:]
        
        var parsed: [ChannelInfo] = []
        
        for channelId in channelOrder {
            let summary = channelsDict[channelId] as? [String: Any] ?? [:]
            let rawAccounts = accountsDict[channelId] as? [[String: Any]] ?? []
            let meta = channelMeta[channelId] as? [String: Any] ?? [:]
            
            let accounts: [ChannelAccountInfo] = rawAccounts.map { acc in
                ChannelAccountInfo(
                    accountId: acc["accountId"] as? String ?? "default",
                    configured: acc["configured"] as? Bool ?? false,
                    enabled: acc["enabled"] as? Bool ?? false,
                    connected: acc["connected"] as? Bool ?? false,
                    loggedIn: acc["loggedIn"] as? Bool ?? false,
                    error: acc["error"] as? String,
                    lastInboundAt: (acc["lastInboundAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) },
                    lastOutboundAt: (acc["lastOutboundAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                )
            }
            
            let configured = summary["configured"] as? Bool ?? false
            let connected = accounts.contains { $0.connected }
            let enabled = accounts.contains { $0.enabled }
            let loggedIn = accounts.contains { $0.loggedIn }
            let error = summary["error"] as? String
            let supportsLogin = (meta["supportsQrLogin"] as? Bool ?? false) ||
                                channelId == "whatsapp"  // WhatsApp always supports QR login
            
            let systemImage: String
            if let img = channelSystemImages[channelId] {
                systemImage = img
            } else {
                // Fallback SF Symbols
                switch channelId {
                case "webchat": systemImage = "globe"
                case "telegram": systemImage = "paperplane.fill"
                case "whatsapp": systemImage = "phone.fill"
                case "discord": systemImage = "gamecontroller.fill"
                case "slack": systemImage = "number"
                case "signal": systemImage = "lock.shield.fill"
                case "imessage": systemImage = "message.fill"
                default: systemImage = "antenna.radiowaves.left.and.right"
                }
            }
            
            let lastInbound = accounts.compactMap(\.lastInboundAt).max()
            let lastOutbound = accounts.compactMap(\.lastOutboundAt).max()
            
            parsed.append(ChannelInfo(
                id: channelId,
                label: channelLabels[channelId] ?? channelId.capitalized,
                detailLabel: channelDetailLabels[channelId],
                systemImage: systemImage,
                configured: configured,
                connected: connected,
                enabled: enabled,
                loggedIn: loggedIn,
                error: error,
                accounts: accounts,
                supportsLogin: supportsLogin,
                lastInboundAt: lastInbound,
                lastOutboundAt: lastOutbound
            ))
        }
        
        channels = parsed
    }
}