import Foundation

/// A long-running command (e.g. `tail -F`) whose stdout is delivered
/// line-by-line to the main actor. Local and SSH use the same invocation
/// builder as one-shot runners, so ControlMaster/askpass behavior matches.
final class LogStream {
    private let process = Process()
    private let pipe = Pipe()
    private var pending = Data()
    private var stopped = false

    /// Called on the main actor for every complete output line.
    var onLine: (@MainActor (String) -> Void)?
    /// Called once on the main actor when the stream ends (nil = clean stop).
    var onEnd: (@MainActor (String?) -> Void)?

    init(target: Target, script: String) {
        let invocation = CommandInvocation.build(for: target, script: script)
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        var env = ProcessInfo.processInfo.environment
        invocation.environment?.forEach { env[$0.key] = $0.value }
        process.environment = env
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
    }

    func start() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        process.terminationHandler = { [weak self] proc in
            guard let self, !self.stopped else { return }
            let message = proc.terminationStatus == 0
                ? nil : "스트림이 종료되었습니다 (코드 \(proc.terminationStatus))"
            Task { @MainActor [weak self] in self?.onEnd?(message) }
        }
        do {
            try process.run()
        } catch {
            let message = error.localizedDescription
            Task { @MainActor [weak self] in self?.onEnd?(message) }
        }
    }

    func stop() {
        stopped = true
        pipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty, !stopped else { return }
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            let lineData = pending.prefix(upTo: newline)
            pending = Data(pending.suffix(from: pending.index(after: newline)))
            let line = String(data: lineData, encoding: .utf8) ?? ""
            Task { @MainActor [weak self] in self?.onLine?(line) }
        }
    }

    deinit {
        stop()
    }
}
