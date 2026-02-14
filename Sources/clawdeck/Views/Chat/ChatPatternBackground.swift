import SwiftUI
import AppKit

/// A tiled image pattern background for the chat area.
///
/// Loads a bundled image and repeats it across the view using
/// `NSColor(patternImage:)`. The pattern opacity can be adjusted.
struct ChatPatternBackground: View {
    var tintColor: Color = .accentColor
    var opacity: Double = 0.15
    var imageName: String = "bg1"

    var body: some View {
        GeometryReader { _ in
            patternFill
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var patternFill: some View {
        if let tile = loadPatternImage() {
            Color(nsColor: NSColor(patternImage: tile))
                .opacity(opacity)
        }
    }

    /// Load the pattern image from the app bundle Resources.
    private func loadPatternImage() -> NSImage? {
        guard let url = Bundle.module.url(forResource: imageName, withExtension: "jpg")
                ?? Bundle.module.url(forResource: imageName, withExtension: "png") else {
            print("[ChatPatternBackground] Could not find \(imageName) in bundle")
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
