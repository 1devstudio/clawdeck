import Foundation
import Observation
import Combine
import Sparkle

/// Manages Sparkle auto-updates.
///
/// Wraps ``SPUStandardUpdaterController`` and exposes a single
/// ``checkForUpdates()`` action plus a bindable ``canCheckForUpdates``
/// flag for the menu item.
@Observable
final class SoftwareUpdateViewModel {
    var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController?
    private var cancellable: AnyCancellable?

    /// The underlying Sparkle updater — exposed so the settings view can
    /// bind to ``SPUUpdater/automaticallyChecksForUpdates`` if needed.
    var updater: SPUUpdater? { updaterController?.updater }

    init() {
        // Sparkle's XPC services require Developer ID signing which is only
        // present in Release/Archive builds. Skip in DEBUG to avoid the
        // "Unable to Check For Updates" error when running from Xcode.
        #if DEBUG
        updaterController = nil
        #else
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif

        cancellable = updater?.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
    }

    /// Trigger a user-initiated update check (shows UI).
    func checkForUpdates() {
        updater?.checkForUpdates()
    }
}
