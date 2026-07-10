import Foundation

/// Persists the kill/restart history (newest first, capped) in UserDefaults.
enum HistoryStore {
    private static let key = "porter.history.v1"
    static let cap = 50

    static func load() -> [HistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    static func save(_ entries: [HistoryEntry]) {
        let capped = Array(entries.prefix(cap))
        if let data = try? JSONEncoder().encode(capped) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
