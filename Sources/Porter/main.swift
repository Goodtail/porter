import Foundation

// Porter entry point.
//   porter                → GUI app
//   porter --scan         → headless port scan of the local machine (F6)
//   porter --scan <host>  → headless port scan of an SSH host

let arguments = CommandLine.arguments

if let scanIndex = arguments.firstIndex(of: "--scan") {
    let target: Target
    if arguments.count > scanIndex + 1 {
        let host = arguments[scanIndex + 1]
        target = Target(id: "cli:\(host)", kind: .ssh, name: host, host: host)
    } else {
        target = .local
    }

    // Headless password auth: PORTER_SSH_PASSWORD=... porter --scan host
    if let password = ProcessInfo.processInfo.environment["PORTER_SSH_PASSWORD"],
       !password.isEmpty {
        SSHPasswordVault.shared.set(password, for: target.id)
    }

    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            let runner = Runners.runner(for: target)
            let result = try await runner.run(Scanner.scanScript)
            let ports = Scanner.parseScan(result.stdout)
            if ports.isEmpty && !result.succeeded {
                FileHandle.standardError.write(Data("scan failed: \(result.stderr)".utf8))
                exit(2)
            }

            // Same project-identity enrichment the GUI shows (one round-trip).
            var projects: [Int: ProjectInfo] = [:]
            let pids = ports.map(\.pid).filter { $0 > 0 }
            if !pids.isEmpty,
               let enriched = try? await runner.run(ProjectInspector.batchScript(pids: pids)) {
                let lookup = Dictionary(ports.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
                projects = ProjectInspector.parse(enriched.stdout, lookup: lookup)
            }

            func pad(_ text: String, _ width: Int) -> String {
                text.count >= width ? text + " " : text.padding(toLength: width, withPad: " ", startingAt: 0)
            }
            print(pad("PORT", 8) + pad("PID", 8) + pad("USER", 13) + pad("PROCESS", 21)
                  + pad("BIND", 12) + pad("CATEGORY", 16) + "PROJECT")
            for entry in ports {
                let project = projects[entry.pid]
                let category = project?.category
                    ?? ProjectInspector.fallbackCategory(command: entry.command, port: entry.port)
                let identity = [project?.framework, project?.name]
                    .compactMap { $0 }.joined(separator: " · ")
                print(pad(String(entry.port), 8) + pad(String(entry.pid), 8)
                      + pad(entry.user, 13) + pad(entry.command, 21)
                      + pad(entry.address, 12) + pad(category.label, 16) + identity)
            }
            print("\n\(ports.count) listening port(s) on \(target.name)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("scan failed: \(error.localizedDescription)\n".utf8))
            exit(2)
        }
    }
    semaphore.wait()
} else {
    PorterApp.main()
}
