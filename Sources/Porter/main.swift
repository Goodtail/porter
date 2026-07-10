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

    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            let result = try await Runners.runner(for: target).run(Scanner.scanScript)
            let ports = Scanner.parseScan(result.stdout)
            if ports.isEmpty && !result.succeeded {
                FileHandle.standardError.write(Data("scan failed: \(result.stderr)".utf8))
                exit(2)
            }
            func pad(_ text: String, _ width: Int) -> String {
                text.count >= width ? text + " " : text.padding(toLength: width, withPad: " ", startingAt: 0)
            }
            print(pad("PORT", 8) + pad("PID", 8) + pad("USER", 13) + pad("PROCESS", 21) + "BIND")
            for entry in ports {
                let label = entry.devLabel.map { "  (\($0))" } ?? ""
                print(pad(String(entry.port), 8) + pad(String(entry.pid), 8)
                      + pad(entry.user, 13) + pad(entry.command, 21)
                      + entry.address + label)
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
