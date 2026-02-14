import AppKit
import Foundation
import CryptoKit

/// Downloads and caches background images to ~/Library/Application Support/ClawdDeck/backgrounds/.
actor BackgroundImageCache {
    static let shared = BackgroundImageCache()

    private let cacheDirectory: URL = {
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

        let localURL = cacheDirectory.appendingPathComponent(key)
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

    private func cacheKey(for url: URL) -> String {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    enum CacheError: Error {
        case invalidImageData
    }
}
