import SwiftUI
import AppKit

/// Renders the inner panel background based on the user's settings.
/// Reads from the `innerPanelBackground` environment value.
struct InnerPanelBackground: View {
    @Environment(\.innerPanelBackground) private var config

    @State private var cachedImage: NSImage?
    @State private var isLoading = false

    var body: some View {
        GeometryReader { geo in
            switch config.mode {
            case .solidColor:
                Rectangle()
                    .fill(Color(hex: config.colorHex))

            case .unsplash:
                if let nsImage = cachedImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(hex: config.colorHex))
                }
            }
        }
        .task(id: config.unsplashURL) {
            await loadUnsplashImage()
        }
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
