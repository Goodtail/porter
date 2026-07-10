import Foundation

struct CommandResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }
}

enum CommandError: LocalizedError {
    case launchFailed(String)
    case failed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let msg): return "실행 실패: \(msg)"
        case .failed(let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "명령이 종료 코드 \(code)로 실패했습니다" : detail
        }
    }
}

/// Executes a POSIX shell script somewhere (locally or over SSH) and returns its output.
/// Local and remote share every scan/parse code path — only the runner differs.
protocol CommandRunner {
    var target: Target { get }
    /// Run `script` with `sh`-compatible semantics. Never throws on non-zero exit;
    /// callers inspect `CommandResult`.
    func run(_ script: String) async throws -> CommandResult
}

// MARK: - Process execution helper

enum Subprocess {
    /// Launch an executable, capture stdout/stderr off the main thread.
    static func run(executable: String, arguments: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = ProcessInfo.processInfo.environment

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: CommandError.launchFailed(error.localizedDescription))
                    return
                }

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                continuation.resume(returning: CommandResult(
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? "",
                    exitCode: process.terminationStatus
                ))
            }
        }
    }
}

// MARK: - Local

struct LocalRunner: CommandRunner {
    let target: Target

    init(target: Target = .local) { self.target = target }

    func run(_ script: String) async throws -> CommandResult {
        try await Subprocess.run(executable: "/bin/zsh", arguments: ["-c", script])
    }

    /// Login shell — picks up nvm/pyenv/asdf PATH. Used only for restarts.
    func runInLoginShell(_ script: String) async throws -> CommandResult {
        try await Subprocess.run(executable: "/bin/zsh", arguments: ["-lc", script])
    }
}

// MARK: - SSH

/// Runs scripts on a remote host through the system `ssh` binary, reusing the
/// user's existing keys, agent and ~/.ssh/config. No credentials are stored.
struct SSHRunner: CommandRunner {
    let target: Target

    /// ControlMaster keeps one TCP+auth session alive so repeated scans are fast.
    private var baseArguments: [String] {
        var args = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=6",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=/tmp/porter-ssh-%r@%h-%p",
            "-o", "ControlPersist=120",
        ]
        if let port = target.port {
            args += ["-p", String(port)]
        }
        args.append(target.sshDestination)
        return args
    }

    func run(_ script: String) async throws -> CommandResult {
        try await Subprocess.run(
            executable: "/usr/bin/ssh",
            arguments: baseArguments + [script]
        )
    }
}

// MARK: - Factory

enum Runners {
    static func runner(for target: Target) -> CommandRunner {
        target.isLocal ? LocalRunner(target: target) : SSHRunner(target: target)
    }
}
