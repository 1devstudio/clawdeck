import SwiftUI
import AppKit

/// A full-cover image background for the inner panel.
///
/// Loads a bundled image and scales it to fill the available space
/// (aspect-fill) so it covers the entire panel without distortion.
struct InnerPanelBackground: View {
    var imageName: String = "bg1"

    var body: some View {
        GeometryReader { geo in
            if let nsImage = loadImage() {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        }
    }

    private func loadImage() -> NSImage? {
        guard let url = Bundle.module.url(forResource: imageName, withExtension: "jpg")
                ?? Bundle.module.url(forResource: imageName, withExtension: "png") else {
            print("[InnerPanelBackground] ❌ \(imageName) not found in bundle")
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
