import SwiftUI
import AppKit

/// A tiled image pattern background.
///
/// Loads a bundled image, draws it at reduced opacity into a tile,
/// and fills the view using `NSColor(patternImage:)`.
struct ChatPatternBackground: View {
    var opacity: Double = 0.20
    var imageName: String = "bg1"

    var body: some View {
        if let image = loadImage() {
            let tile = createTile(image: image, opacity: opacity)
            Color(nsColor: NSColor(patternImage: tile))
        }
    }

    private func loadImage() -> NSImage? {
        guard let url = Bundle.module.url(forResource: imageName, withExtension: "jpg")
                ?? Bundle.module.url(forResource: imageName, withExtension: "png") else {
            print("[ChatPatternBackground] ❌ \(imageName) not found in bundle")
            return nil
        }
        return NSImage(contentsOf: url)
    }

    /// Create a tile with adjusted opacity for subtle tiling.
    private func createTile(image: NSImage, opacity: Double) -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: CGFloat(opacity)
        )
        result.unlockFocus()
        return result
    }
}
