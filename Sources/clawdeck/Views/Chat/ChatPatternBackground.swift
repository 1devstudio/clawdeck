import SwiftUI
import AppKit

/// Injects a tiled pattern image into the enclosing NSScrollView.
///
/// Place inside a ScrollView's content. It walks up the AppKit view
/// hierarchy, finds the parent NSScrollView, and inserts a custom
/// pattern-drawing NSView behind all content.
struct ChatPatternBackground: NSViewRepresentable {
    var opacity: Double = 0.20
    var imageName: String = "bg1"

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.frame = .zero
        // Delay to ensure the scroll view hierarchy is fully built
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            applyPattern(from: view, context: context)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func applyPattern(from view: NSView, context: Context) {
        guard let scrollView = findScrollView(from: view) else {
            print("[ChatPatternBackground] ❌ Could not find NSScrollView")
            return
        }

        // Don't add duplicate pattern views
        guard !scrollView.subviews.contains(where: { $0 is TiledPatternView }) else {
            print("[ChatPatternBackground] ⏭️ Pattern already applied")
            return
        }

        guard let image = loadImage() else {
            print("[ChatPatternBackground] ❌ Could not load image")
            return
        }

        // Make scroll view and clip view transparent
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false

        // Insert a custom tiled-pattern view behind all content
        let patternView = TiledPatternView(patternImage: image, patternOpacity: opacity)
        patternView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(patternView, positioned: .below, relativeTo: scrollView.contentView)

        NSLayoutConstraint.activate([
            patternView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            patternView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            patternView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            patternView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
        ])

        print("[ChatPatternBackground] ✅ Inserted TiledPatternView into NSScrollView")
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
}

// MARK: - TiledPatternView

/// Custom NSView that draws a tiled image pattern across its entire bounds.
final class TiledPatternView: NSView {
    private let patternImage: NSImage
    private let patternOpacity: Double

    init(patternImage: NSImage, patternOpacity: Double) {
        self.patternImage = patternImage
        self.patternOpacity = patternOpacity
        super.init(frame: .zero)
        wantsLayer = true
        // Don't intercept mouse events — pass through to scroll content
        // (handled by hitTest returning nil below)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass all events through to the scroll content
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.saveGState()
        ctx.setAlpha(CGFloat(patternOpacity))

        let tileSize = patternImage.size
        guard tileSize.width > 0, tileSize.height > 0 else { return }

        // Draw tiles across the dirty rect
        let startX = floor(dirtyRect.minX / tileSize.width) * tileSize.width
        let startY = floor(dirtyRect.minY / tileSize.height) * tileSize.height

        var y = startY
        while y < dirtyRect.maxY {
            var x = startX
            while x < dirtyRect.maxX {
                let tileRect = NSRect(origin: CGPoint(x: x, y: y), size: tileSize)
                patternImage.draw(in: tileRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                x += tileSize.width
            }
            y += tileSize.height
        }

        ctx.restoreGState()
    }
}
