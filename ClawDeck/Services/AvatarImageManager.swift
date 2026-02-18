import AppKit
import Foundation

/// Manages avatar images on disk at ~/Library/Application Support/clawdeck/avatars/.
enum AvatarImageManager {

    /// The avatars directory, created lazily.
    static let avatarsDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("clawdeck/avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Save an image for a given binding ID. Returns the filename on success.
    /// Images are resized to fit within 256×256 and saved as PNG.
    static func saveAvatar(image: NSImage, bindingId: String) throws -> String {
        let filename = "\(bindingId).png"
        let url = avatarsDirectory.appendingPathComponent(filename)

        guard let pngData = resizeAndEncode(image: image, maxDimension: 256) else {
            throw AvatarError.encodingFailed
        }

        try pngData.write(to: url, options: .atomic)
        return filename
    }

    /// Load an avatar image by filename.
    static func loadAvatar(named filename: String) -> NSImage? {
        let url = avatarsDirectory.appendingPathComponent(filename)
        return NSImage(contentsOf: url)
    }

    /// Delete an avatar file.
    static func deleteAvatar(named filename: String) {
        let url = avatarsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private static func resizeAndEncode(image: NSImage, maxDimension: CGFloat) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }

        let w = CGFloat(bitmap.pixelsWide)
        let h = CGFloat(bitmap.pixelsHigh)
        let longest = max(w, h)

        let targetBitmap: NSBitmapImageRep
        if longest > maxDimension {
            let scale = maxDimension / longest
            let newW = Int(w * scale)
            let newH = Int(h * scale)

            guard let resized = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: newW, pixelsHigh: newH,
                bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            ) else { return nil }

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
            NSGraphicsContext.current?.imageInterpolation = .high
            bitmap.draw(in: NSRect(x: 0, y: 0, width: newW, height: newH))
            NSGraphicsContext.restoreGraphicsState()
            targetBitmap = resized
        } else {
            targetBitmap = bitmap
        }

        return targetBitmap.representation(using: .png, properties: [:])
    }

    enum AvatarError: Error, LocalizedError {
        case encodingFailed
        var errorDescription: String? { "Failed to encode avatar image" }
    }
}
