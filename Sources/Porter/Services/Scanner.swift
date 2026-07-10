import Foundation

/// Builds shell scripts and parses their output. Shared by local and SSH targets;
/// remote round-trips are minimized by batching everything into single scripts.
enum Scanner {

    // MARK: - Port scan

    /// Lists listening TCP sockets. Prefers `lsof` (macOS + most Linux),
    /// falls back to `ss` (Linux without lsof). `@@`-markers tell the parser
    /// which format it is looking at.
    static let scanScript = """
    if command -v lsof >/dev/null 2>&1; then
      echo "@@LSOF"
      lsof -nP -iTCP -sTCP:LISTEN -FpcuLn 2>/dev/null
    else
      echo "@@SS"
      ss -ltnpH 2>/dev/null
      echo "@@PS"
      ps -eo pid=,user= 2>/dev/null
    fi
    """

    static func parseScan(_ output: String) -> [PortEntry] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let first = lines.first else { return [] }
        let entries: [PortEntry]
        if first == "@@LSOF" {
            entries = parseLsof(lines.dropFirst())
        } else if first == "@@SS" {
            entries = parseSS(lines.dropFirst())
        } else {
            entries = []
        }
        return dedupe(entries).sorted { $0.port < $1.port }
    }

    /// lsof -F output: one field per line, first char is the field tag.
    /// p=pid c=command u=uid L=login n=socket name. A process set (p,c,u,L)
    /// applies to every following n line until the next p.
    private static func parseLsof(_ lines: ArraySlice<String>) -> [PortEntry] {
        var entries: [PortEntry] = []
        var pid = 0
        var command = "?"
        var user = "?"

        for line in lines {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int(value) ?? 0
            case "c": command = value
            case "L": user = value
            case "n":
                if let (address, port) = splitAddressPort(value), pid > 0 {
                    entries.append(PortEntry(port: port, address: address, proto: "TCP",
                                             pid: pid, command: command, user: user))
                }
            default: break // u (uid), f (fd), t (type) — unused
            }
        }
        return entries
    }

    /// ss -ltnpH lines look like:
    /// `LISTEN 0 4096 0.0.0.0:3000 0.0.0.0:* users:(("node",pid=1234,fd=23))`
    /// The trailing process column is absent for other users' processes.
    private static func parseSS(_ lines: ArraySlice<String>) -> [PortEntry] {
        var socketLines: [String] = []
        var userByPid: [Int: String] = [:]
        var inPS = false

        for line in lines {
            if line == "@@PS" { inPS = true; continue }
            if inPS {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2, let pid = Int(parts[0]) {
                    userByPid[pid] = String(parts[1])
                }
            } else {
                socketLines.append(line)
            }
        }

        let pidRegex = try! NSRegularExpression(pattern: #"\"([^\"]+)\",pid=(\d+)"#)
        var entries: [PortEntry] = []

        for line in socketLines {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard columns.count >= 4, let (address, port) = splitAddressPort(columns[3]) else { continue }

            var pid = 0
            var command = "?"
            if let last = columns.last, last.hasPrefix("users:"),
               let match = pidRegex.firstMatch(in: last, range: NSRange(last.startIndex..., in: last)),
               let cmdRange = Range(match.range(at: 1), in: last),
               let pidRange = Range(match.range(at: 2), in: last) {
                command = String(last[cmdRange])
                pid = Int(last[pidRange]) ?? 0
            }
            entries.append(PortEntry(port: port, address: address, proto: "TCP",
                                     pid: pid, command: command,
                                     user: userByPid[pid] ?? "?"))
        }
        return entries
    }

    /// "…addr:port" → (addr, port). Handles `*:3000`, `127.0.0.1:5432`, `[::1]:8080`, `[::]:80`.
    static func splitAddressPort(_ name: String) -> (String, Int)? {
        guard let idx = name.lastIndex(of: ":"), let port = Int(name[name.index(after: idx)...]) else {
            return nil
        }
        var address = String(name[..<idx])
        address = address.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if address.isEmpty || address == "::" || address == "0.0.0.0" { address = "*" }
        return (address, port)
    }

    /// Same pid listening on the same port via IPv4 and IPv6 → one row.
    /// Prefer the wildcard address so reachability reads correctly.
    private static func dedupe(_ entries: [PortEntry]) -> [PortEntry] {
        var best: [String: PortEntry] = [:]
        for entry in entries {
            let key = "\(entry.pid):\(entry.port)"
            if let existing = best[key] {
                if existing.address != "*" && entry.address == "*" { best[key] = entry }
            } else {
                best[key] = entry
            }
        }
        return Array(best.values)
    }

    // MARK: - Tailscale

    /// Best-effort Tailscale IPv4 of a machine. The CLI often isn't on PATH
    /// (macOS app-bundle installs), so several locations are probed; the
    /// final fallback greps interfaces for a CGNAT (100.64/10) address.
    static let tailscaleScript = """
    for bin in tailscale /Applications/Tailscale.app/Contents/MacOS/Tailscale /usr/local/bin/tailscale /opt/homebrew/bin/tailscale; do
      if [ -x "$bin" ] || command -v "$bin" >/dev/null 2>&1; then
        ip=$("$bin" ip -4 2>/dev/null | head -1)
        if [ -n "$ip" ]; then echo "$ip"; exit 0; fi
      fi
    done
    (ifconfig 2>/dev/null || ip addr 2>/dev/null) | grep -oE 'inet 100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.[0-9]+\\.[0-9]+' | head -1 | awk '{print $2}'
    exit 0
    """

    static func parseTailscaleIP(_ output: String) -> String? {
        let ip = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n").first ?? ""
        let parts = ip.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ Int($0) != nil }) else { return nil }
        return ip
    }

    // MARK: - Process detail

    private static let marker = "@@PORTER@@"

    /// One round-trip for everything the detail panel needs (F3).
    static func detailScript(pid: Int) -> String {
        """
        ps -o ppid=,user=,pcpu=,pmem= -p \(pid) 2>/dev/null | head -1
        echo "\(marker)"
        ps -o lstart= -p \(pid) 2>/dev/null
        echo "\(marker)"
        ps -o command= -p \(pid) 2>/dev/null | head -c 4000
        echo
        echo "\(marker)"
        lsof -p \(pid) -a -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'
        echo "\(marker)"
        lsof -p \(pid) 2>/dev/null | awk '$5=="REG" {print $NF}' | grep -Ei '(\\.log$|/logs?/)' | sort -u | head -15
        """
    }

    static func parseDetail(_ output: String, pid: Int, fallbackUser: String) -> ProcessDetail? {
        let sections = output.components(separatedBy: marker).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard sections.count >= 5 else { return nil }

        let statFields = sections[0].split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let fullCommand = sections[2]
        guard !fullCommand.isEmpty else { return nil } // process already gone

        var detail = ProcessDetail(
            pid: pid, ppid: nil, user: fallbackUser, cpu: nil, mem: nil,
            started: sections[1], fullCommand: fullCommand,
            cwd: sections[3].isEmpty ? nil : sections[3],
            logFiles: sections[4].isEmpty ? [] : sections[4]
                .split(separator: "\n").map(String.init)
        )
        if statFields.count >= 4 {
            detail.ppid = Int(statFields[0])
            detail.user = statFields[1]
            detail.cpu = Double(statFields[2])
            detail.mem = Double(statFields[3])
        }
        return detail
    }

    // MARK: - Control

    static func killScript(pid: Int, force: Bool) -> String {
        "kill -\(force ? "KILL" : "TERM") \(pid)"
    }

    static func aliveScript(pid: Int) -> String {
        "kill -0 \(pid) 2>/dev/null && echo ALIVE || echo DEAD"
    }

    /// Relaunch a process detached from Porter, in its recorded cwd (F4.3).
    ///
    /// The command runs under `$SHELL -lc` so nvm/brew PATH from the user's
    /// login profile is available — critical over SSH, where the session shell
    /// is non-login and `node` is typically not on PATH. After spawning we
    /// verify the process survived 1.2s; if it died instantly we say so and
    /// emit the log tail instead of reporting fake success.
    static func restartScript(command: String, cwd: String, logPath: String?) -> String {
        let quotedCwd = shellQuote(cwd)
        let quotedCommand = shellQuote(command)
        let logSetup: String
        let redirect: String
        let deadDiagnostics: String
        if let logPath {
            logSetup = "LOG=\"\(logPath)\"\nmkdir -p \"$(dirname \"$LOG\")\"\n"
            redirect = ">>\"$LOG\" 2>&1"
            deadDiagnostics = "tail -n 5 \"$LOG\" 2>/dev/null"
        } else {
            logSetup = ""
            redirect = ">/dev/null 2>&1"
            deadDiagnostics = ""
        }
        return """
        \(logSetup)cd \(quotedCwd) || { echo PORTER_CDFAIL; exit 0; }
        nohup "${SHELL:-/bin/sh}" -lc \(quotedCommand) \(redirect) &
        PORTER_PID=$!
        sleep 1.2
        if kill -0 $PORTER_PID 2>/dev/null; then
          echo "PORTER_OK $PORTER_PID"
        else
          echo PORTER_DEAD
          \(deadDiagnostics)
        fi
        """
    }

    enum RestartOutcome: Equatable {
        case started(pid: String)
        case diedInstantly(logTail: String)
        case badDirectory
    }

    static func parseRestartResult(_ output: String) -> RestartOutcome? {
        let lines = output.split(separator: "\n").map(String.init)
        if lines.contains("PORTER_CDFAIL") { return .badDirectory }
        if let ok = lines.first(where: { $0.hasPrefix("PORTER_OK") }) {
            return .started(pid: ok.replacingOccurrences(of: "PORTER_OK", with: "")
                .trimmingCharacters(in: .whitespaces))
        }
        if let deadIndex = lines.firstIndex(of: "PORTER_DEAD") {
            let tail = lines.dropFirst(deadIndex + 1).joined(separator: " · ")
            return .diedInstantly(logTail: tail)
        }
        return nil
    }

    static func tailScript(file: String, lines: Int = 120) -> String {
        "tail -n \(lines) \(shellQuote(file)) 2>/dev/null"
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
