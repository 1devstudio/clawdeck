import SwiftUI
import AppKit

/// A Telegram-style tiled pattern background for the chat area.
///
/// Draws small geometric shapes (circles, diamonds, stars, hearts) into a
/// tile image and repeats it across the view using `NSColor(patternImage:)`.
/// The pattern is tinted with the current theme color at low opacity.
struct ChatPatternBackground: View {
    var tintColor: Color = .accentColor
    var opacity: Double = 0.06

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { _ in
            patternFill
                .ignoresSafeArea()
        }
    }

    private var patternFill: some View {
        let tileSize = CGSize(width: 120, height: 120)
        let nsColor = NSColor(tintColor)
        let shapeColor = colorScheme == .dark
            ? nsColor.blended(withFraction: 0.3, of: .white) ?? nsColor
            : nsColor.blended(withFraction: 0.2, of: .black) ?? nsColor

        let tile = generateTile(size: tileSize, color: shapeColor)
        let patternColor = NSColor(patternImage: tile)

        return Color(nsColor: patternColor)
            .opacity(opacity)
    }

    // MARK: - Tile Generation

    /// Generate a single tile image with scattered geometric shapes.
    private func generateTile(size: CGSize, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let ctx = NSGraphicsContext.current!.cgContext
        ctx.setFillColor(color.cgColor)

        // Shape placements within the tile — offset grid with variety.
        // Each entry: (x, y, shapeIndex, scale)
        let placements: [(CGFloat, CGFloat, Int, CGFloat)] = [
            (15, 12, 0, 0.7),    // small circle
            (65, 8, 2, 0.8),     // star
            (105, 20, 1, 0.6),   // diamond
            (38, 35, 3, 0.65),   // heart
            (85, 42, 0, 0.55),   // circle
            (10, 58, 2, 0.6),    // star
            (55, 55, 1, 0.75),   // diamond
            (98, 65, 3, 0.5),    // heart
            (25, 82, 1, 0.6),    // diamond
            (70, 88, 0, 0.65),   // circle
            (110, 95, 2, 0.55),  // star
            (45, 105, 3, 0.7),   // heart
            (90, 110, 1, 0.5),   // diamond
        ]

        for (x, y, shape, scale) in placements {
            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            ctx.scaleBy(x: scale, y: scale)

            switch shape {
            case 0: drawCircle(ctx: ctx)
            case 1: drawDiamond(ctx: ctx)
            case 2: drawStar(ctx: ctx)
            case 3: drawHeart(ctx: ctx)
            default: drawCircle(ctx: ctx)
            }

            ctx.restoreGState()
        }

        image.unlockFocus()
        return image
    }

    // MARK: - Shape Drawing

    private func drawCircle(ctx: CGContext) {
        let r: CGFloat = 4
        ctx.fillEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
    }

    private func drawDiamond(ctx: CGContext) {
        let s: CGFloat = 5
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -s))
        path.addLine(to: CGPoint(x: s, y: 0))
        path.addLine(to: CGPoint(x: 0, y: s))
        path.addLine(to: CGPoint(x: -s, y: 0))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }

    private func drawStar(ctx: CGContext) {
        let outer: CGFloat = 5
        let inner: CGFloat = 2.2
        let points = 5
        let path = CGMutablePath()

        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = (CGFloat(i) * .pi / CGFloat(points)) - (.pi / 2)
            let point = CGPoint(
                x: cos(angle) * radius,
                y: sin(angle) * radius
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }

    private func drawHeart(ctx: CGContext) {
        let s: CGFloat = 4.5
        let path = CGMutablePath()
        // Simple heart using two arcs and a point
        path.move(to: CGPoint(x: 0, y: s * 0.4))
        path.addCurve(
            to: CGPoint(x: 0, y: -s * 0.5),
            control1: CGPoint(x: -s, y: -s * 0.2),
            control2: CGPoint(x: -s, y: -s)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: s * 0.4),
            control1: CGPoint(x: s, y: -s),
            control2: CGPoint(x: s, y: -s * 0.2)
        )
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }
}
