import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {

    // MARK: Targets
    @Published var targets: [Target]
    @Published var selectedTargetID: Target.ID = Target.local.id
    @Published var connectionStates: [Target.ID: ConnectionState] = [:]

    // MARK: Scan results
    @Published var ports: [PortEntry] = []
    @Published var isScanning = false
    @Published var scanError: String?
    @Published var lastScanDate: Date?

    // MARK: Selection / detail
    @Published var selectedPortID: PortEntry.ID?
    @Published var detail: ProcessDetail?
    @Published var isLoadingDetail = false
    @Published var logPreview: String?
    @Published var logPreviewFile: String?

    // MARK: UI state
    @Published var searchText = ""
    @Published var autoRefresh = true { didSet { configureTimer() } }
    @Published var events: [ActivityEvent] = []
    @Published var feedCollapsed = false
    @Published var killCandidate: PortEntry?      // opens KillConfirmSheet
    @Published var restartCandidate: PortEntry?   // opens RestartConfirmSheet
    @Published var showAddTarget = false
    @Published var isActing = false               // kill/restart in flight

    private var timer: Timer?
    private var scanGeneration = 0

    init() {
        var all: [Target] = [.local]
        all += SSHConfigParser.targetsFromDefaultConfig()
        all += TargetStore.load()
        targets = all
        configureTimer()
    }

    var selectedTarget: Target {
        targets.first { $0.id == selectedTargetID } ?? .local
    }

    var selectedPort: PortEntry? {
        ports.first { $0.id == selectedPortID }
    }

    var filteredPorts: [PortEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return ports }
        return ports.filter {
            String($0.port).contains(query)
                || $0.command.lowercased().contains(query)
                || String($0.pid).contains(query)
                || $0.user.lowercased().contains(query)
        }
    }

    /// searchText is a pure port number that nothing occupies → "port is free" (F2.5).
    var searchedFreePort: Int? {
        guard let port = Int(searchText.trimmingCharacters(in: .whitespaces)),
              (1...65535).contains(port),
              !ports.contains(where: { $0.port == port }),
              !isScanning, scanError == nil else { return nil }
        return port
    }

    // MARK: - Target switching

    func select(target: Target) {
        guard target.id != selectedTargetID else { return }
        selectedTargetID = target.id
        ports = []
        selectedPortID = nil
        detail = nil
        logPreview = nil
        logPreviewFile = nil
        scanError = nil
        Task { await refresh() }
    }

    func addTarget(name: String, host: String, user: String, port: Int?) {
        let label = name.isEmpty ? host : name
        let target = Target(id: "custom:\(UUID().uuidString)", kind: .ssh,
                            name: label, host: host, user: user, port: port)
        targets.append(target)
        TargetStore.save(targets)
        log(.info, "SSH 타깃 추가: \(label)")
        select(target: target)
    }

    func removeTarget(_ target: Target) {
        guard target.kind == .ssh, !target.fromSSHConfig else { return }
        targets.removeAll { $0.id == target.id }
        TargetStore.save(targets)
        if selectedTargetID == target.id { select(target: .local) }
    }

    // MARK: - Scanning

    func refresh() async {
        let target = selectedTarget
        scanGeneration += 1
        let generation = scanGeneration
        isScanning = true
        if connectionStates[target.id] == nil { connectionStates[target.id] = .checking }

        do {
            let result = try await Runners.runner(for: target).run(Scanner.scanScript)
            guard generation == scanGeneration, target.id == selectedTargetID else { return }

            if result.stdout.isEmpty && !result.succeeded {
                throw CommandError.failed(exitCode: result.exitCode, stderr: result.stderr)
            }
            let newPorts = Scanner.parseScan(result.stdout)
            let changed = newPorts.map(\.id) != ports.map(\.id)
            ports = newPorts
            scanError = nil
            connectionStates[target.id] = .connected
            lastScanDate = Date()
            if changed { log(.info, "스캔: LISTEN 포트 \(newPorts.count)개") }
            // Keep selection stable across refreshes; drop it if the process died.
            if let sel = selectedPortID, !newPorts.contains(where: { $0.id == sel }) {
                selectedPortID = nil
                detail = nil
            }
        } catch {
            guard generation == scanGeneration, target.id == selectedTargetID else { return }
            let message = error.localizedDescription
            scanError = message
            connectionStates[target.id] = .failed(message)
            log(.error, "스캔 실패: \(message)")
        }
        isScanning = false
    }

    private func configureTimer() {
        timer?.invalidate()
        guard autoRefresh else { timer = nil; return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isActing, !self.isScanning else { return }
                await self.refresh()
            }
        }
    }

    // MARK: - Detail

    func selectPort(_ entry: PortEntry?) {
        selectedPortID = entry?.id
        detail = nil
        logPreview = nil
        logPreviewFile = nil
        guard let entry else { return }
        Task { await loadDetail(for: entry) }
    }

    private func loadDetail(for entry: PortEntry) async {
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            let result = try await Runners.runner(for: selectedTarget)
                .run(Scanner.detailScript(pid: entry.pid))
            guard selectedPortID == entry.id else { return }
            detail = Scanner.parseDetail(result.stdout, pid: entry.pid, fallbackUser: entry.user)
        } catch {
            guard selectedPortID == entry.id else { return }
            log(.error, "상세 조회 실패 (PID \(entry.pid)): \(error.localizedDescription)")
        }
    }

    func loadLogPreview(file: String) {
        let target = selectedTarget
        logPreviewFile = file
        logPreview = nil
        Task {
            do {
                let result = try await Runners.runner(for: target).run(Scanner.tailScript(file: file))
                guard logPreviewFile == file else { return }
                logPreview = result.stdout.isEmpty ? "(비어 있음)" : result.stdout
            } catch {
                logPreview = "로그를 읽을 수 없습니다: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Control (F4)

    /// SIGTERM, verify, report. Returns true when the process is gone.
    @discardableResult
    func kill(_ entry: PortEntry, force: Bool) async -> Bool {
        let target = selectedTarget
        isActing = true
        defer { isActing = false }
        do {
            let runner = Runners.runner(for: target)
            let result = try await runner.run(Scanner.killScript(pid: entry.pid, force: force))
            if !result.succeeded {
                throw CommandError.failed(exitCode: result.exitCode, stderr: result.stderr)
            }
            // Give SIGTERM a moment, then verify.
            try? await Task.sleep(nanoseconds: force ? 300_000_000 : 1_200_000_000)
            let alive = try await runner.run(Scanner.aliveScript(pid: entry.pid))
            let dead = alive.stdout.contains("DEAD")
            if dead {
                log(.success, "\(force ? "강제 종료" : "종료"): \(entry.command) (PID \(entry.pid), :\(entry.port))")
            } else {
                log(.warning, "\(entry.command) (PID \(entry.pid))가 SIGTERM 후에도 살아있습니다 — Force Kill을 사용하세요")
            }
            await refresh()
            return dead
        } catch {
            log(.error, "종료 실패 (PID \(entry.pid)): \(error.localizedDescription)")
            await refresh()
            return false
        }
    }

    /// Kill + relaunch with the recorded command in the recorded cwd.
    func restart(_ entry: PortEntry, command: String, cwd: String) async {
        let target = selectedTarget
        isActing = true
        defer { isActing = false }
        do {
            let runner = Runners.runner(for: target)
            _ = try await runner.run(Scanner.killScript(pid: entry.pid, force: false))
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            let script = Scanner.restartScript(command: command, cwd: cwd)
            let result: CommandResult
            if let local = runner as? LocalRunner {
                result = try await local.runInLoginShell(script)
            } else {
                result = try await runner.run(script)
            }
            if result.succeeded {
                let newPid = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                log(.success, "재시작: \(entry.command) :\(entry.port) → 새 PID \(newPid)")
            } else {
                throw CommandError.failed(exitCode: result.exitCode, stderr: result.stderr)
            }
        } catch {
            log(.error, "재시작 실패 (\(entry.command)): \(error.localizedDescription)")
        }
        try? await Task.sleep(nanoseconds: 800_000_000)
        await refresh()
    }

    // MARK: - Activity feed

    func log(_ kind: ActivityEvent.Kind, _ message: String) {
        events.append(ActivityEvent(date: Date(), kind: kind,
                                    targetName: selectedTarget.name, message: message))
        if events.count > 300 { events.removeFirst(events.count - 300) }
    }
}
