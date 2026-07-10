import Foundation

// MARK: - Target

/// A machine Porter can inspect: the local Mac or a remote host over SSH.
struct Target: Identifiable, Hashable, Codable {
    enum Kind: Codable, Hashable {
        case local
        case ssh
    }

    var id: String
    var kind: Kind
    /// Display label ("My Mac", "gpu-server", …)
    var name: String
    /// SSH host (alias from ~/.ssh/config or hostname/IP). Empty for local.
    var host: String = ""
    /// Optional SSH user. Empty → let ssh config decide.
    var user: String = ""
    /// Optional SSH port. nil → default/config.
    var port: Int?
    /// True when parsed from ~/.ssh/config (not user-created, not deletable).
    var fromSSHConfig: Bool = false

    static let local = Target(id: "local", kind: .local, name: "My Mac")

    var isLocal: Bool { kind == .local }

    /// "user@host" or "host" for display and ssh invocation.
    var sshDestination: String {
        user.isEmpty ? host : "\(user)@\(host)"
    }

    var subtitle: String {
        switch kind {
        case .local: return "localhost"
        case .ssh: return sshDestination + (port.map { ":\($0)" } ?? "")
        }
    }
}

enum ConnectionState: Equatable {
    case unknown
    case checking
    case connected
    case failed(String)

    var isFailed: Bool { if case .failed = self { return true }; return false }
}

// MARK: - Port / Process

/// One listening TCP socket, owned by a process.
struct PortEntry: Identifiable, Hashable {
    let port: Int
    let address: String      // "*", "127.0.0.1", "::1", …
    let proto: String        // "TCP"
    let pid: Int
    let command: String      // short process name as reported by lsof/ss
    let user: String

    var id: String { "\(pid):\(port):\(address)" }

    /// Well-known dev-tool label for this port, if any.
    var devLabel: String? { DevPortCatalog.label(for: port) }

    /// Loopback-only sockets can't be reached from other machines.
    var isLoopbackOnly: Bool {
        address.hasPrefix("127.") || address == "::1" || address == "localhost"
    }
}

/// Rich detail for a single process, fetched on selection.
struct ProcessDetail: Equatable {
    var pid: Int
    var ppid: Int?
    var user: String
    var cpu: Double?
    var mem: Double?
    var started: String
    var fullCommand: String
    var cwd: String?
    var logFiles: [String]

    /// Heuristic: killing this is probably a mistake.
    var isProtected: Bool {
        if user == "root" { return true }
        if pid < 300 { return true }
        let sysPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/"]
        if sysPrefixes.contains(where: { fullCommand.hasPrefix($0) }) { return true }
        let critical = ["launchd", "WindowServer", "kernel_task", "sshd", "loginwindow"]
        let first = fullCommand.split(separator: " ").first.map(String.init) ?? fullCommand
        let base = (first as NSString).lastPathComponent
        return critical.contains(base)
    }
}

// MARK: - Activity Feed

struct ActivityEvent: Identifiable {
    enum Kind {
        case info, success, warning, error
    }
    let id = UUID()
    let date: Date
    let kind: Kind
    let targetName: String
    let message: String
}

// MARK: - Dev Port Catalog

/// Well-known development ports → human label (F2.3).
enum DevPortCatalog {
    static let map: [Int: String] = [
        3000: "Node · Next.js", 3001: "Node alt", 4000: "Phoenix · dev",
        4200: "Angular", 4321: "Astro", 5000: "Flask · AirPlay",
        5173: "Vite", 5174: "Vite alt", 5432: "PostgreSQL",
        5555: "Prisma Studio", 6006: "Storybook", 6379: "Redis",
        7860: "Gradio", 8000: "Django · FastAPI", 8025: "Mailpit",
        8080: "HTTP alt", 8081: "Metro · RN", 8501: "Streamlit",
        8787: "Wrangler", 8888: "Jupyter", 9000: "PHP-FPM · SonarQube",
        9090: "Prometheus", 9200: "Elasticsearch", 11434: "Ollama",
        1420: "Tauri", 19000: "Expo", 27017: "MongoDB", 3306: "MySQL",
        54321: "Supabase", 54322: "Supabase DB",
    ]

    static func label(for port: Int) -> String? { map[port] }

    /// Ports developers care about most — used for subtle row emphasis.
    static func isDevPort(_ port: Int) -> Bool { map[port] != nil }
}

// MARK: - Process command icon

enum ProcessIcon {
    /// SF Symbol name for a process, keyed off its command name.
    static func symbol(for command: String) -> String {
        let c = command.lowercased()
        if c.contains("node") || c.contains("bun") || c.contains("deno") { return "hexagon.fill" }
        if c.contains("python") || c.contains("uvicorn") || c.contains("gunicorn") { return "chevron.left.forwardslash.chevron.right" }
        if c.contains("docker") || c.contains("containerd") { return "shippingbox.fill" }
        if c.contains("postgres") || c.contains("mysql") || c.contains("redis") || c.contains("mongo") { return "cylinder.split.1x2.fill" }
        if c.contains("java") || c.contains("gradle") { return "cup.and.saucer.fill" }
        if c.contains("ruby") || c.contains("puma") { return "diamond.fill" }
        if c.contains("go") || c.contains("caddy") { return "tortoise.fill" }
        if c.contains("nginx") || c.contains("httpd") { return "arrow.triangle.branch" }
        if c.contains("ssh") { return "network" }
        if c.contains("claude") || c.contains("codex") || c.contains("ollama") { return "sparkles" }
        return "terminal.fill"
    }
}
