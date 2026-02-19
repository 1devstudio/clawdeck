import Foundation

/// Persists the set of starred (pinned) session keys in UserDefaults.
/// Thread-safe: all mutations go through a single `@MainActor` observable.
@Observable
@MainActor
final class StarredSessionsStore {

    /// The set of starred session keys.
    private(set) var starredKeys: Set<String> = []

    /// UserDefaults key.
    private static let storageKey = "com.clawdbot.deck.starredSessions"

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - Queries

    func isStarred(_ sessionKey: String) -> Bool {
        starredKeys.contains(sessionKey)
    }

    // MARK: - Mutations

    func toggle(_ sessionKey: String) {
        if starredKeys.contains(sessionKey) {
            starredKeys.remove(sessionKey)
        } else {
            starredKeys.insert(sessionKey)
        }
        save()
    }

    func star(_ sessionKey: String) {
        guard starredKeys.insert(sessionKey).inserted else { return }
        save()
    }

    func unstar(_ sessionKey: String) {
        guard starredKeys.remove(sessionKey) != nil else { return }
        save()
    }

    /// Remove keys that no longer exist in the given set of valid session keys.
    func prune(validKeys: Set<String>) {
        let stale = starredKeys.subtracting(validKeys)
        guard !stale.isEmpty else { return }
        starredKeys.subtract(stale)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let array = UserDefaults.standard.stringArray(forKey: Self.storageKey) else { return }
        starredKeys = Set(array)
    }

    private func save() {
        UserDefaults.standard.set(Array(starredKeys), forKey: Self.storageKey)
    }
}
