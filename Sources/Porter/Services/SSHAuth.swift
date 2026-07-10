import Foundation
import Security

// MARK: - Auth failure detection

enum SSHAuth {
    /// True when ssh failed at authentication AND the server offers an
    /// interactive method we can satisfy with a password. A pure
    /// "Permission denied (publickey)" server can't be helped by prompting.
    static func canRetryWithPassword(_ message: String) -> Bool {
        message.contains("Permission denied")
            && (message.contains("password") || message.contains("keyboard-interactive"))
    }

    static func keychainAccount(for target: Target) -> String {
        "\(target.sshDestination):\(target.port ?? 22)"
    }

    /// ssh has no "read password from stdin" mode — it insists on a TTY unless
    /// SSH_ASKPASS points at a helper program. We install a tiny script that
    /// echoes the password ssh asks for; the password itself travels in an
    /// environment variable of the ssh process, never on a command line or disk.
    static func ensureAskpassHelper() -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Porter", isDirectory: true)
        let helper = dir.appendingPathComponent("porter-askpass.sh")
        let script = "#!/bin/sh\nprintf '%s\\n' \"$PORTER_SSH_PASSWORD\"\n"

        if (try? String(contentsOf: helper, encoding: .utf8)) != script {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? script.write(to: helper, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        }
        return helper.path
    }
}

// MARK: - In-memory password vault

/// Session-scoped passwords, keyed by target id. Thread-safe because
/// SSHRunner reads it off the main actor.
final class SSHPasswordVault: @unchecked Sendable {
    static let shared = SSHPasswordVault()

    private let lock = NSLock()
    private var storage: [String: String] = [:]

    func password(for targetID: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[targetID]
    }

    func set(_ password: String?, for targetID: String) {
        lock.lock(); defer { lock.unlock() }
        storage[targetID] = password
    }
}

// MARK: - Keychain (opt-in persistence)

enum Keychain {
    private static let service = "com.porter.ssh"

    static func save(_ password: String, account: String) {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(password.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
