import Foundation

/// Reads Host aliases from ~/.ssh/config so the user's existing machines
/// appear in the sidebar with zero setup (F1.2).
enum SSHConfigParser {

    static func targetsFromDefaultConfig() -> [Target] {
        let path = NSString(string: "~/.ssh/config").expandingTildeInPath
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return parse(content)
    }

    static func parse(_ content: String) -> [Target] {
        var targets: [Target] = []
        var seen = Set<String>()

        for rawLine in content.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2, parts[0].lowercased() == "host" else { continue }

            for alias in parts.dropFirst() {
                // Skip patterns and negations — they aren't connectable names.
                guard !alias.contains("*"), !alias.contains("?"), !alias.hasPrefix("!") else { continue }
                guard !seen.contains(alias) else { continue }
                seen.insert(alias)
                targets.append(Target(
                    id: "sshconfig:\(alias)",
                    kind: .ssh,
                    name: alias,
                    host: alias,            // alias resolves via ssh config itself
                    fromSSHConfig: true
                ))
            }
        }
        return targets
    }
}
