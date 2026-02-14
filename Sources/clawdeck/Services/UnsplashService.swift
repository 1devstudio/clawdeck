import Foundation

/// Lightweight Unsplash client using the public /napi/ endpoints (no API key needed).
actor UnsplashService {
    private let session = URLSession.shared
    private let baseURL = "https://unsplash.com/napi"

    struct UnsplashPhoto: Identifiable, Sendable {
        let id: String
        let thumbURL: URL
        let regularURL: URL
        let photographer: String
    }

    func search(query: String, page: Int = 1, perPage: Int = 30) async throws -> [UnsplashPhoto] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        var components = URLComponents(string: "\(baseURL)/search/photos")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]

        let (data, _) = try await session.data(from: components.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = json?["results"] as? [[String: Any]] ?? []

        return results.compactMap { Self.parsePhoto($0) }
    }

    private static func parsePhoto(_ dict: [String: Any]) -> UnsplashPhoto? {
        guard let id = dict["id"] as? String,
              let urls = dict["urls"] as? [String: String],
              let thumb = urls["thumb"].flatMap(URL.init(string:)),
              let regular = urls["regular"].flatMap(URL.init(string:)),
              let user = dict["user"] as? [String: Any],
              let name = user["name"] as? String else {
            return nil
        }

        return UnsplashPhoto(
            id: id,
            thumbURL: thumb,
            regularURL: regular,
            photographer: name
        )
    }
}
