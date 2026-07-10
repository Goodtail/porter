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
                          message: "Porter 시작"),
            ActivityEvent(date: now.addingTimeInterval(-255), kind: .info, targetName: targetName,
                          message: "스캔: LISTEN 포트 7개"),
            ActivityEvent(date: now.addingTimeInterval(-140), kind: .success, targetName: targetName,
                          message: "종료: node (PID 51002, :5174)"),
            ActivityEvent(date: now.addingTimeInterval(-62), kind: .success, targetName: "gpu-server",
                          message: "재시작: uvicorn :8000 → 새 PID 48844"),
            ActivityEvent(date: now.addingTimeInterval(-8), kind: .info, targetName: targetName,
                          message: "종료 감지: node (PID 50113) — 목록 갱신"),
        ]
    }
}
