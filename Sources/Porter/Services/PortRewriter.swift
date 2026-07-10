import Foundation

/// Rewrites a dev-server command to listen on a different port.
/// Handles the common conventions; anything else falls back to a PORT env
/// prefix — and the result is always shown in an editable field before running.
enum PortRewriter {
    static func rewrite(command: String, from oldPort: Int, to newPort: Int) -> String {
        guard oldPort != newPort else { return command }
        let old = String(oldPort), new = String(newPort)
        var result = sanitize(command)
        var matched = false

        // --port 3000 / --port=3000 / -p 3000 / PORT=3000 (only when the number
        // matches the port we're moving away from).
        let patterns = [
            #"(--port[= ])"# + old + #"\b"#,
            #"(-p )"# + old + #"\b"#,
            #"(\bPORT=)"# + old + #"\b"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            if regex.firstMatch(in: result, range: range) != nil {
                result = regex.stringByReplacingMatches(in: result, range: range,
                                                        withTemplate: "$1" + new)
                matched = true
            }
        }
        if matched { return result }

        // A PORT= with some other number (e.g. from an older edit) — update it
        // rather than stacking another prefix in front.
        if let regex = try? NSRegularExpression(pattern: #"\bPORT=\d+"#) {
            let range = NSRange(result.startIndex..., in: result)
            if regex.firstMatch(in: result, range: range) != nil {
                return regex.stringByReplacingMatches(in: result, range: range,
                                                      withTemplate: "PORT=" + new)
            }
        }
        return "PORT=\(new) \(result)"
    }

    /// Collapses stacked env prefixes ("PORT=3000 PORT=3000 cmd" → "PORT=3000 cmd").
    /// History entries written by older builds can carry this pollution.
    static func sanitize(_ command: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"^(?:PORT=\d+\s+)+(?=PORT=\d+\s)"#) else {
            return command
        }
        let range = NSRange(command.startIndex..., in: command)
        return regex.stringByReplacingMatches(in: command, range: range, withTemplate: "")
    }

    /// ~/.porter/logs/<name>-<port>.log — restarts redirect here so the new
    /// process has a streamable log from second zero.
    static func managedLogPath(name: String?, command: String, port: Int) -> String {
        let raw = name ?? command.split(separator: " ").first.map(String.init) ?? "process"
        let slug = raw.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let cleaned = String(slug).split(separator: "-").joined(separator: "-")
        return "$HOME/.porter/logs/\(cleaned.isEmpty ? "process" : cleaned)-\(port).log"
    }
}
