import Foundation

/// Reads each process's working directory and sniffs project manifests
/// (package.json, pyproject.toml, go.mod, …) to answer: *what service is
/// this?* All PIDs are inspected in ONE batched script — a single SSH
/// round-trip regardless of process count.
enum ProjectInspector {

    // MARK: - Script

    static func batchScript(pids: [Int]) -> String {
        let list = Array(Set(pids)).sorted().map(String.init).joined(separator: " ")
        return """
        for pid in \(list); do
          echo "@@PID:$pid"
          cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)
          [ -z "$cwd" ] && [ -e "/proc/$pid/cwd" ] && cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null)
          echo "@@CWD:$cwd"
          if [ -n "$cwd" ] && [ -d "$cwd" ]; then
            [ -f "$cwd/package.json" ]     && { echo "@@PKG"; head -c 3000 "$cwd/package.json"; echo; }
            [ -f "$cwd/pyproject.toml" ]   && { echo "@@PY"; head -c 1500 "$cwd/pyproject.toml"; echo; }
            [ -f "$cwd/requirements.txt" ] && { echo "@@RQ"; head -c 800 "$cwd/requirements.txt"; echo; }
            [ -f "$cwd/go.mod" ]           && { echo "@@GO"; head -1 "$cwd/go.mod"; }
            [ -f "$cwd/Cargo.toml" ]       && { echo "@@RS"; head -c 600 "$cwd/Cargo.toml"; echo; }
            [ -f "$cwd/Gemfile" ]          && { echo "@@RB"; head -c 600 "$cwd/Gemfile"; echo; }
            [ -f "$cwd/pnpm-lock.yaml" ]   && echo "@@PNPM"
            [ -f "$cwd/yarn.lock" ]        && echo "@@YARN"
            { [ -f "$cwd/bun.lockb" ] || [ -f "$cwd/bun.lock" ]; } && echo "@@BUN"
          fi
        done
        true
        """
    }

    // MARK: - Parsing

    /// `lookup` maps pid → one of its port entries (for fallback classification).
    static func parse(_ output: String, lookup: [Int: PortEntry]) -> [Int: ProjectInfo] {
        var result: [Int: ProjectInfo] = [:]
        var pid: Int?
        var cwd = ""
        var sections: [String: String] = [:]
        var marker: String?

        func flush() {
            guard let p = pid else { return }
            let entry = lookup[p]
            result[p] = detect(cwd: cwd, sections: sections,
                               command: entry?.command ?? "", port: entry?.port ?? 0)
        }

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("@@PID:") {
                flush()
                pid = Int(line.dropFirst(6))
                cwd = ""; sections = [:]; marker = nil
            } else if line.hasPrefix("@@CWD:") {
                cwd = String(line.dropFirst(6))
            } else if ["@@PKG", "@@PY", "@@RQ", "@@GO", "@@RS", "@@RB",
                       "@@PNPM", "@@YARN", "@@BUN"].contains(line) {
                marker = line
                if ["@@PNPM", "@@YARN", "@@BUN"].contains(line) {
                    sections[line] = "" // presence flag, no content follows
                }
            } else if let m = marker {
                sections[m, default: ""] += line + "\n"
            }
        }
        flush()
        return result
    }

    // MARK: - Detection

    /// Substring checks instead of strict JSON/TOML parsing — manifests are
    /// truncated by `head -c`, and scripts like `"dev": "next dev"` identify
    /// the framework even when the dependency block got cut off.
    static func detect(cwd: String, sections: [String: String],
                       command: String, port: Int) -> ProjectInfo {
        var name: String?
        var framework: String?
        var category: ServiceCategory?
        var devCommand: String?

        if let pkg = sections["@@PKG"] {
            name = firstMatch(#""name"\s*:\s*"([^"]+)""#, in: pkg)
            if pkg.contains("\"dev\"") {
                if sections["@@PNPM"] != nil { devCommand = "pnpm dev" }
                else if sections["@@YARN"] != nil { devCommand = "yarn dev" }
                else if sections["@@BUN"] != nil { devCommand = "bun dev" }
                else { devCommand = "npm run dev" }
            }
            let signatures: [(String, String, ServiceCategory)] = [
                ("\"next\"", "Next.js", .frontend), ("next dev", "Next.js", .frontend),
                ("\"nuxt\"", "Nuxt", .frontend),
                ("\"astro\"", "Astro", .frontend),
                ("@sveltejs/kit", "SvelteKit", .frontend),
                ("@remix-run", "Remix", .frontend),
                ("@angular/core", "Angular", .frontend),
                ("react-scripts", "CRA", .frontend),
                ("\"expo\"", "Expo · RN", .frontend), ("expo start", "Expo · RN", .frontend),
                ("@nestjs/", "NestJS", .backend),
                ("\"fastify\"", "Fastify", .backend),
                ("\"express\"", "Express", .backend),
                ("\"koa\"", "Koa", .backend),
                ("\"hono\"", "Hono", .backend),
                ("\"svelte\"", "Svelte", .frontend),
                ("\"vite\"", "Vite", .frontend),
                ("\"react\"", "React", .frontend),
            ]
            if let hit = signatures.first(where: { pkg.contains($0.0) }) {
                framework = hit.1; category = hit.2
            } else {
                framework = "Node.js"; category = .backend
            }
        } else if sections["@@PY"] != nil || sections["@@RQ"] != nil {
            let py = (sections["@@PY"] ?? "") + (sections["@@RQ"] ?? "")
            name = firstMatch(#"name\s*=\s*"([^"]+)""#, in: sections["@@PY"] ?? "")
            let signatures: [(String, String, ServiceCategory)] = [
                ("django", "Django", .backend),
                ("fastapi", "FastAPI", .backend),
                ("flask", "Flask", .backend),
                ("streamlit", "Streamlit", .ai),
                ("gradio", "Gradio", .ai),
                ("jupyter", "Jupyter", .ai),
                ("torch", "PyTorch", .ai),
                ("tensorflow", "TensorFlow", .ai),
                ("uvicorn", "Uvicorn", .backend),
            ]
            if let hit = signatures.first(where: { py.lowercased().contains($0.0) }) {
                framework = hit.1; category = hit.2
            } else {
                framework = "Python"; category = .backend
            }
        } else if let go = sections["@@GO"] {
            name = go.split(separator: "/").last.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            framework = "Go"; category = .backend
        } else if let rs = sections["@@RS"] {
            name = firstMatch(#"name\s*=\s*"([^"]+)""#, in: rs)
            framework = "Rust"; category = .backend
        } else if let rb = sections["@@RB"] {
            framework = rb.contains("rails") ? "Rails" : "Ruby"; category = .backend
        }

        if name == nil, !cwd.isEmpty {
            // Directory basename as a last resort — but only when it looks like
            // a project, not a system location (ollama's cwd is /var → "var").
            let base = (cwd as NSString).lastPathComponent
            let meaningless: Set<String> = ["/", "var", "tmp", "private", "usr", "etc",
                                            "opt", "root", "home", "Library", "System",
                                            "Applications", "bin", "sbin"]
            if !meaningless.contains(base) && !base.isEmpty {
                name = base
            }
        }
        return ProjectInfo(name: name, framework: framework,
                           category: category ?? fallbackCategory(command: command, port: port),
                           devCommand: devCommand)
    }

    /// True when ps reported a rewritten process title, not a runnable command
    /// ("next-server (v15.3.2)"). Relaunching such a string can never work.
    static func looksLikeRetitledProcess(_ command: String) -> Bool {
        command.contains(" (")
    }

    /// Classification when no manifest is readable — by command name, then port.
    static func fallbackCategory(command: String, port: Int) -> ServiceCategory {
        let c = command.lowercased()
        let databases = ["postgres", "mysql", "mariadb", "redis", "mongo", "clickhouse",
                         "memcached", "etcd", "elastic", "opensearch", "qdrant", "weaviate",
                         "chroma", "milvus", "neo4j", "influx", "cockroach", "couch", "minio"]
        if databases.contains(where: c.contains) { return .database }
        if [5432, 3306, 6379, 27017, 9200, 6333, 7687, 8086, 9000].contains(port),
           c != "?" && !c.isEmpty {
            // well-known DB port but unrecognized command — still likely a DB
            return .database
        }
        let ai = ["ollama", "lmstudio", "lm studio", "llama", "vllm", "comfyui", "invokeai"]
        if ai.contains(where: c.contains) || port == 11434 { return .ai }
        let backends = ["uvicorn", "gunicorn", "java", "dotnet", "php", "puma",
                        "nginx", "caddy", "httpd", "traefik"]
        if backends.contains(where: c.contains) { return .backend }
        return .other
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
