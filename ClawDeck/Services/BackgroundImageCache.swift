import AppKit
import Foundation
import CryptoKit

/// Downloads and caches background images to ~/Library/Application Support/ClawdDeck/backgrounds/.
actor BackgroundImageCache {
    static let shared = BackgroundImageCache()

    /// Shared cache directory — static so it's accessible from nonisolated contexts too.
    static let cacheDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ClawdDeck/backgrounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var memoryCache: [String: NSImage] = [:]

    func image(for remoteURL: URL) async throws -> NSImage {
        let key = cacheKey(for: remoteURL)

        if let cached = memoryCache[key] {
            return cached
        }

        let localURL = Self.cacheDirectory.appendingPathComponent(key)
        if FileManager.default.fileExists(atPath: localURL.path),
           let nsImage = NSImage(contentsOf: localURL) {
            memoryCache[key] = nsImage
            return nsImage
        }

        let (data, _) = try await URLSession.shared.data(from: remoteURL)
        try data.write(to: localURL, options: .atomic)

        guard let nsImage = NSImage(data: data) else {
            throw CacheError.invalidImageData
        }
        memoryCache[key] = nsImage
        return nsImage
    }

    /// Synchronously load a cached image from disk (no network, no actor hop).
    /// Call from the main thread to get an instant result on app launch.
    nonisolated func cachedImageSync(for remoteURL: URL) -> NSImage? {
        let key = cacheKeySync(for: remoteURL)
        let localURL = Self.cacheDirectory.appendingPathComponent(key)
        guard FileManager.default.fileExists(atPath: localURL.path) else { return nil }
        return NSImage(contentsOf: localURL)
    }

    private func cacheKey(for url: URL) -> String {
        cacheKeySync(for: url)
    }

    nonisolated private func cacheKeySync(for url: URL) -> String {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    enum CacheError: Error {
        case invalidImageData
    }
}
