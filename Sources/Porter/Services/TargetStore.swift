import Foundation

/// Persists user-added SSH targets (F1.3) in UserDefaults as JSON.
enum TargetStore {
    private static let key = "porter.customTargets.v1"

    static func load() -> [Target] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let targets = try? JSONDecoder().decode([Target].self, from: data) else { return [] }
        return targets
    }

    static func save(_ targets: [Target]) {
        let custom = targets.filter { $0.kind == .ssh && !$0.fromSSHConfig }
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
