import SwiftUI
import AppKit

/// Sets a tiled pattern image as the background of the enclosing NSScrollView.
///
/// Place this view inside a ScrollView's content. It uses NSViewRepresentable
/// to walk up the AppKit view hierarchy, find the parent NSScrollView, and
/// set its backgroundColor to an NSColor(patternImage:) tile.
struct ChatPatternBackground: NSViewRepresentable {
    var opacity: Double = 0.20
    var imageName: String = "bg1"

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.frame = .zero
        DispatchQueue.main.async {
            applyPattern(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-apply if the view hierarchy changes
        DispatchQueue.main.async {
            applyPattern(from: nsView)
        }
    }

    private func applyPattern(from view: NSView) {
        guard let scrollView = findScrollView(from: view) else {
            print("[ChatPatternBackground] ❌ Could not find NSScrollView in hierarchy")
            return
        }

        guard let image = loadImage() else {
            print("[ChatPatternBackground] ❌ Could not load image")
            return
        }

        // Create a tinted, semi-transparent version of the pattern
        let tintedImage = createTintedTile(image: image, opacity: opacity)
        let patternColor = NSColor(patternImage: tintedImage)

        scrollView.drawsBackground = true
        scrollView.backgroundColor = patternColor

        // Also make the clip view transparent so the pattern shows through
        scrollView.contentView.drawsBackground = false

        print("[ChatPatternBackground] ✅ Applied pattern to NSScrollView")
    }

    private func findScrollView(from view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let v = current {
            if let scrollView = v as? NSScrollView {
                return scrollView
            }
            current = v.superview
        }
        return nil
    }

    private func loadImage() -> NSImage? {
        guard let url = Bundle.module.url(forResource: imageName, withExtension: "jpg")
                ?? Bundle.module.url(forResource: imageName, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    /// Create a copy of the image with adjusted opacity for use as a subtle pattern.
    private func createTintedTile(image: NSImage, opacity: Double) -> NSImage {
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
