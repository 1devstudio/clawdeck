import Foundation
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

    private let updaterController: SPUStandardUpdaterController
    private var cancellable: AnyCancellable?

    /// The underlying Sparkle updater — exposed so the settings view can
    /// bind to ``SPUUpdater/automaticallyChecksForUpdates`` if needed.
    var updater: SPUUpdater { updaterController.updater }

    init() {
        // `startingUpdater: true` begins the update cycle on launch
        // (background check respecting SUEnableAutomaticChecks).
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
    }

    /// Trigger a user-initiated update check (shows UI).
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
