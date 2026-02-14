import SwiftUI
import AppKit

/// A tiled image pattern background for the chat area.
///
/// Loads a bundled image and repeats it across the view using
/// `NSColor(patternImage:)`. The pattern opacity can be adjusted.
struct ChatPatternBackground: View {
    var opacity: Double = 0.15
    var imageName: String = "bg1"

    var body: some View {
        if let tile = loadPatternImage() {
            Color(nsColor: NSColor(patternImage: tile))
                .opacity(opacity)
                .ignoresSafeArea()
        } else {
            // Debug fallback — shows red if the image fails to load
            Color.red.opacity(0.2)
                .ignoresSafeArea()
                .onAppear {
                    print("[ChatPatternBackground] ⚠️ Could not load \(imageName)")
                }
        }
    }

    /// Load the pattern image from the app bundle Resources.
    private func loadPatternImage() -> NSImage? {
        // Try Bundle.module (SPM processed resources)
        if let url = Bundle.module.url(forResource: imageName, withExtension: "jpg")
                ?? Bundle.module.url(forResource: imageName, withExtension: "png") {
            print("[ChatPatternBackground] ✅ Found image at: \(url.path)")
            return NSImage(contentsOf: url)
        }

        print("[ChatPatternBackground] ❌ \(imageName) not found in Bundle.module")
        return nil
    }
}
