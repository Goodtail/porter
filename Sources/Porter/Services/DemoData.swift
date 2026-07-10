import AppKit
import Foundation

/// Launch flags. `--demo` fills the UI with curated fake data (nice for
/// trying the UI without real processes); `--screenshot <dir>` additionally
/// captures README shots and exits. Demo data keeps real machine/port
/// information out of published screenshots.
enum LaunchMode {
    static let screenshotDir: String? = {
        guard let index = CommandLine.arguments.firstIndex(of: "--screenshot"),
              CommandLine.arguments.count > index + 1 else { return nil }
        return CommandLine.arguments[index + 1]
    }()

    static var isDemo: Bool {
        screenshotDir != nil || CommandLine.arguments.contains("--demo")
    }
}

enum DemoData {
    static let sshTargets: [Target] = [
        Target(id: "demo:gpu", kind: .ssh, name: "gpu-server", host: "10.0.0.42", user: "ubuntu"),
        Target(id: "demo:home", kind: .ssh, name: "home-lab", host: "homelab.local", user: "pi"),
        Target(id: "demo:staging", kind: .ssh, name: "staging", host: "staging.acme.dev", user: "deploy", port: 2222),
    ]

    static let ports: [PortEntry] = [
        PortEntry(port: 3000, address: "*", proto: "TCP", pid: 48213, command: "node", user: "dev"),
        PortEntry(port: 5173, address: "127.0.0.1", proto: "TCP", pid: 48371, command: "node", user: "dev"),
        PortEntry(port: 5432, address: "127.0.0.1", proto: "TCP", pid: 981, command: "postgres", user: "dev"),
        PortEntry(port: 6379, address: "127.0.0.1", proto: "TCP", pid: 1027, command: "redis-server", user: "dev"),
        PortEntry(port: 8000, address: "127.0.0.1", proto: "TCP", pid: 49118, command: "python3.12", user: "dev"),
        PortEntry(port: 8888, address: "*", proto: "TCP", pid: 47552, command: "python3.12", user: "dev"),
        PortEntry(port: 11434, address: "127.0.0.1", proto: "TCP", pid: 902, command: "ollama", user: "dev"),
    ]

    static let projects: [Int: ProjectInfo] = [
        48213: ProjectInfo(name: "acme-web", framework: "Next.js", category: .frontend,
                           devCommand: "npm run dev"),
        48371: ProjectInfo(name: "acme-admin", framework: "Vite", category: .frontend),
        49118: ProjectInfo(name: "acme-api", framework: "FastAPI", category: .backend),
        47552: ProjectInfo(name: "research", framework: "Jupyter", category: .ai),
        902: ProjectInfo(name: nil, framework: nil, category: .ai),
        981: ProjectInfo(name: nil, framework: nil, category: .database),
        1027: ProjectInfo(name: nil, framework: nil, category: .database),
    ]

    /// Letter-tile stand-ins for real favicons (demo can't fetch over HTTP).
    static var favicons: [String: NSImage] {
        let specs: [(String, String, NSColor)] = [
            ("localhost:3000", "N", NSColor.black),
            ("localhost:5173", "V", NSColor(red: 0.39, green: 0.29, blue: 0.93, alpha: 1)),
            ("localhost:8000", "F", NSColor(red: 0.02, green: 0.59, blue: 0.53, alpha: 1)),
            ("localhost:8888", "J", NSColor(red: 0.95, green: 0.45, blue: 0.11, alpha: 1)),
        ]
        var result: [String: NSImage] = [:]
        for (key, letter, color) in specs {
            result[key] = letterTile(letter, background: color)
        }
        return result
    }

    private static func letterTile(_ letter: String, background: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            background.setFill()
            path.fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 19, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let text = NSAttributedString(string: letter, attributes: attrs)
            let size = text.size()
            text.draw(at: NSPoint(x: (rect.width - size.width) / 2,
                                  y: (rect.height - size.height) / 2))
            return true
        }
    }

    static var history: [HistoryEntry] {
        let now = Date()
        return [
            HistoryEntry(id: UUID(), date: now.addingTimeInterval(-140), action: .kill,
                         targetID: Target.local.id, targetName: "My Mac", port: 5174,
                         command: "node", fullCommand: "node ./node_modules/.bin/vite --port 5174",
                         cwd: "/Users/dev/acme-admin", projectName: "acme-admin", framework: "Vite"),
            HistoryEntry(id: UUID(), date: now.addingTimeInterval(-3900), action: .restart,
                         targetID: "demo:gpu", targetName: "gpu-server", port: 8000,
                         command: "python3.12",
                         fullCommand: "python3.12 -m uvicorn app.main:api --reload --port 8000",
                         cwd: "/home/ubuntu/acme-api", projectName: "acme-api", framework: "FastAPI"),
        ]
    }

    static func detail(for entry: PortEntry) -> ProcessDetail {
        switch entry.port {
        case 3000:
            return ProcessDetail(
                pid: entry.pid, ppid: 48200, user: "dev", cpu: 12.4, mem: 1.8,
                started: "Thu Jul 10 09:12:44 2026",
                fullCommand: "node /Users/dev/acme-web/node_modules/.bin/next dev --turbo",
                cwd: "/Users/dev/acme-web",
                logFiles: ["/Users/dev/acme-web/logs/dev.log"]
            )
        case 8000:
            return ProcessDetail(
                pid: entry.pid, ppid: 49100, user: "dev", cpu: 3.1, mem: 0.9,
                started: "Thu Jul 10 10:02:11 2026",
                fullCommand: "python3.12 -m uvicorn app.main:api --reload --port 8000",
                cwd: "/Users/dev/acme-api",
                logFiles: ["/Users/dev/acme-api/logs/uvicorn.log"]
            )
        default:
            return ProcessDetail(
                pid: entry.pid, ppid: 1, user: entry.user, cpu: 0.4, mem: 0.6,
                started: "Thu Jul 10 08:40:03 2026",
                fullCommand: "\(entry.command) --port \(entry.port)",
                cwd: "/Users/dev",
                logFiles: []
            )
        }
    }

    static let logTail = """
      ▲ Next.js 15.3.2 (turbo)
      - Local:    http://localhost:3000
      - Network:  http://192.168.0.12:3000

     ✓ Ready in 1284ms
     ○ Compiling / ...
     ✓ Compiled / in 812ms
     GET / 200 in 921ms
     GET /api/session 200 in 38ms
     POST /api/checkout 201 in 187ms
    """

    static func seedEvents(targetName: String) -> [ActivityEvent] {
        let now = Date()
        return [
            ActivityEvent(date: now.addingTimeInterval(-260), kind: .info, targetName: targetName,
                          message: L("Porter 시작")),
            ActivityEvent(date: now.addingTimeInterval(-255), kind: .info, targetName: targetName,
                          message: L("스캔: LISTEN 포트 7개")),
            ActivityEvent(date: now.addingTimeInterval(-140), kind: .success, targetName: targetName,
                          message: L("종료: node (PID 51002, :5174)")),
            ActivityEvent(date: now.addingTimeInterval(-62), kind: .success, targetName: "gpu-server",
                          message: L("재시작: uvicorn :8000 → 새 PID 48844")),
            ActivityEvent(date: now.addingTimeInterval(-8), kind: .info, targetName: targetName,
                          message: L("종료 감지: node (PID 50113) — 목록 갱신")),
        ]
    }
}
