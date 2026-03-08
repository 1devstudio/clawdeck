import SwiftUI
import AppKit

/// Renders the inner panel background based on the user's settings.
/// Reads from the `innerPanelBackground` environment value.
struct InnerPanelBackground: View {
    @Environment(\.innerPanelBackground) private var config
    @Environment(\.colorScheme) private var colorScheme

    @State private var cachedImage: NSImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            switch config.mode {
            case .none:
                Color(nsColor: .windowBackgroundColor)
                    .overlay(
                        (colorScheme == .dark ? Color.white : Color.black)
                            .opacity(0.06)
                    )

            case .solidColor:
                Rectangle()
                    .fill(Color(hex: config.colorHex))

            case .unsplash:
                if let nsImage = cachedImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(hex: config.colorHex))
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            // Try synchronous disk cache first for instant display on launch
            loadCachedImageSync()
        }
        .task(id: config.unsplashURL) {
            await loadUnsplashImage()
        }
    }

    /// Synchronously load from disk cache — no actor hop, no async.
    /// Gives an instant background on app launch even if a Keychain dialog or
    /// other modal is blocking the run loop.
    private func loadCachedImageSync() {
        guard config.mode == .unsplash,
              cachedImage == nil,
              let url = URL(string: config.unsplashURL) else { return }
        cachedImage = BackgroundImageCache.shared.cachedImageSync(for: url)
    }

    private func loadUnsplashImage() async {
        guard config.mode == .unsplash,
              let url = URL(string: config.unsplashURL) else {
            cachedImage = nil
            return
        }

        isLoading = true
        do {
            cachedImage = try await BackgroundImageCache.shared.image(for: url)
        } catch {
            cachedImage = nil
        }
        isLoading = false
    }
}
