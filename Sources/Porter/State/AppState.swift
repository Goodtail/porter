import AppKit
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

    // MARK: Live log streaming
    @Published var liveLogLines: [String] = []
    @Published var isStreamingLog = false
    @Published var streamingFile: String?
    private var logStream: LogStream?

    // MARK: Project intelligence
    /// pid → detected project info, for the currently selected target.
    @Published var projects: [Int: ProjectInfo] = [:]
    /// target id → Tailscale IPv4 (only successful probes).
    @Published var tailscaleIPs: [Target.ID: String] = [:]
    private var tailscaleProbed: Set<Target.ID> = []
    private var projectFetchInFlight = false

    // MARK: UI state
    @Published var searchText = ""
    @Published var groupByCategory = true
    @Published var autoRefresh = true { didSet { configureTimer() } }
    @Published var events: [ActivityEvent] = []
    @Published var feedCollapsed = false
    @Published var killCandidate: PortEntry?      // opens KillConfirmSheet
    @Published var restartCandidate: PortEntry?   // opens RestartConfirmSheet
    @Published var showAddTarget = false
    @Published var isActing = false               // kill/restart in flight

    // MARK: SSH password prompt
    @Published var passwordPromptTarget: Target?  // opens PasswordPromptSheet
    @Published var passwordPromptError: String?
    /// Targets whose last scan failed on auth — auto-refresh holds off until
    /// a password arrives, so the timer doesn't spam failures or re-open sheets.
    private var authBlocked: Set<Target.ID> = []

    private var timer: Timer?
    private var scanGeneration = 0
    /// Local PIDs watched via kqueue for instant exit detection.
    private var processWatchers: [Int: DispatchSourceProcess] = [:]
    /// Window occlusion — no point polling while nobody can see the result.
    private var windowVisible = true
    /// Demo mode: curated fake data, no shell access (screenshots, UI tours).
    let isDemo: Bool

    init(demo: Bool = false) {
        isDemo = demo
        if demo {
            // autoRefresh stays true for honest UI, but no timer is configured
            // and refresh() is a demo no-op — nothing ever polls.
            targets = [.local] + DemoData.sshTargets
            ports = DemoData.ports
            connectionStates = [Target.local.id: .connected, "demo:gpu": .connected]
            lastScanDate = Date()
            events = DemoData.seedEvents(targetName: Target.local.name)
            projects = DemoData.projects
            tailscaleIPs = [Target.local.id: "100.84.12.7"]
            return
        }
        var all: [Target] = [.local]
        all += SSHConfigParser.targetsFromDefaultConfig()
        all += TargetStore.load()
        targets = all
        configureTimer()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeOcclusionStateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let visible = NSApp.occlusionState.contains(.visible)
                let becameVisible = visible && !self.windowVisible
                self.windowVisible = visible
                if becameVisible, !self.isScanning, !self.isActing {
                    await self.refresh() // catch up immediately on re-focus
                }
            }
        }
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
        stopLogStream()
        scanError = nil
        if isDemo {
            ports = DemoData.ports
            connectionStates[target.id] = .connected
            return
        }
        projects = [:]
        authBlocked.remove(target.id)
        clearProcessWatchers()

        // Saved password from a previous session? Load it before first contact.
        if !target.isLocal, SSHPasswordVault.shared.password(for: target.id) == nil,
           let stored = Keychain.load(account: SSHAuth.keychainAccount(for: target)) {
            SSHPasswordVault.shared.set(stored, for: target.id)
        }

        configureTimer() // interval differs for local vs remote
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
        SSHPasswordVault.shared.set(nil, for: target.id)
        Keychain.delete(account: SSHAuth.keychainAccount(for: target))
        if selectedTargetID == target.id { select(target: .local) }
    }

    // MARK: - Scanning

    func refresh() async {
        guard !isDemo else { return }
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
            authBlocked.remove(target.id)
            connectionStates[target.id] = .connected
            lastScanDate = Date()
            if changed { log(.info, "스캔: LISTEN 포트 \(newPorts.count)개") }
            // Keep selection stable across refreshes; drop it if the process died.
            if let sel = selectedPortID, !newPorts.contains(where: { $0.id == sel }) {
                selectedPortID = nil
                detail = nil
            }
            // Local processes get push-based exit detection on top of polling.
            if target.isLocal {
                syncProcessWatchers(pids: Set(newPorts.map(\.pid).filter { $0 > 0 }))
            }
            // Best-effort enrichment, off the critical path.
            Task { await fetchProjectsIfNeeded() }
            if !tailscaleProbed.contains(target.id) {
                tailscaleProbed.insert(target.id)
                Task { await probeTailscale(target) }
            }
        } catch {
            guard generation == scanGeneration, target.id == selectedTargetID else { return }
            let message = error.localizedDescription
            scanError = message
            connectionStates[target.id] = .failed(message)
            log(.error, "스캔 실패: \(message)")

            // Auth failure on a target whose server accepts passwords → prompt (F1.5+).
            if !target.isLocal, SSHAuth.canRetryWithPassword(message) {
                let hadPassword = SSHPasswordVault.shared.password(for: target.id) != nil
                let firstFailure = !authBlocked.contains(target.id)
                authBlocked.insert(target.id)
                if passwordPromptTarget == nil, firstFailure {
                    passwordPromptError = hadPassword
                        ? "인증에 실패했습니다 — 비밀번호를 다시 확인하세요."
                        : nil
                    passwordPromptTarget = target
                }
            }
        }
        isScanning = false
    }

    /// Poll cadence: local snapshots are ~free (3s); remote rides an existing
    /// ControlMaster session but still crosses the network (6s).
    var refreshIntervalSeconds: Int { selectedTarget.isLocal ? 3 : 6 }

    private func configureTimer() {
        timer?.invalidate()
        guard autoRefresh else { timer = nil; return }
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshIntervalSeconds),
                                     repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isActing, !self.isScanning else { return }
                guard self.windowVisible else { return }               // nobody's looking
                guard self.passwordPromptTarget == nil else { return } // user is typing
                guard !self.authBlocked.contains(self.selectedTargetID) else { return }
                await self.refresh()
            }
        }
    }

    // MARK: - Project intelligence (what service is this?)

    func category(for entry: PortEntry) -> ServiceCategory {
        projects[entry.pid]?.category
            ?? ProjectInspector.fallbackCategory(command: entry.command, port: entry.port)
    }

    /// Inspect cwd/manifests for pids we haven't classified yet — one batched
    /// script call, silent on failure (enrichment is never worth an error banner).
    private func fetchProjectsIfNeeded() async {
        guard !isDemo, !projectFetchInFlight else { return }
        let unknown = ports.filter { $0.pid > 0 && projects[$0.pid] == nil }
        guard !unknown.isEmpty else { return }
        projectFetchInFlight = true
        defer { projectFetchInFlight = false }

        let target = selectedTarget
        do {
            let result = try await Runners.runner(for: target)
                .run(ProjectInspector.batchScript(pids: unknown.map(\.pid)))
            guard target.id == selectedTargetID else { return }
            let lookup = Dictionary(unknown.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
            let detected = ProjectInspector.parse(result.stdout, lookup: lookup)
            projects.merge(detected) { _, new in new }
        } catch { /* best-effort */ }
    }

    private func probeTailscale(_ target: Target) async {
        do {
            let result = try await Runners.runner(for: target).run(Scanner.tailscaleScript)
            if let ip = Scanner.parseTailscaleIP(result.stdout) {
                tailscaleIPs[target.id] = ip
                log(.info, "Tailscale 감지: \(ip)")
            }
        } catch { /* best-effort */ }
    }

    // MARK: - Open in browser

    struct PortURL: Identifiable {
        let label: String
        let url: URL
        var id: String { url.absoluteString }
    }

    /// Reachable URLs for a port: localhost (local target), the SSH host
    /// (remote, non-loopback binds), and the machine's Tailscale IP when
    /// detected. Databases don't speak HTTP — no URLs for them.
    func urls(for entry: PortEntry) -> [PortURL] {
        guard category(for: entry) != .database else { return [] }
        let target = selectedTarget
        let tailscale = tailscaleIPs[target.id]
        var list: [PortURL] = []

        func append(_ label: String, host: String) {
            guard let url = URL(string: "http://\(host):\(entry.port)") else { return }
            guard !list.contains(where: { $0.url == url }) else { return }
            list.append(PortURL(label: label, url: url))
        }

        if target.isLocal {
            append("localhost", host: "localhost")
            if let tailscale { append("Tailscale", host: tailscale) }
        } else if !entry.isLoopbackOnly {
            if let tailscale, tailscale == target.host {
                append("Tailscale", host: tailscale)
            } else {
                append(target.host, host: target.host)
                if let tailscale { append("Tailscale", host: tailscale) }
            }
        }
        return list
    }

    func open(_ portURL: PortURL) {
        NSWorkspace.shared.open(portURL.url)
        log(.info, "브라우저 열기: \(portURL.url.absoluteString)")
    }

    // MARK: - SSH password flow

    func submitPassword(_ password: String, saveToKeychain: Bool) {
        guard let target = passwordPromptTarget else { return }
        SSHPasswordVault.shared.set(password, for: target.id)
        if saveToKeychain {
            Keychain.save(password, account: SSHAuth.keychainAccount(for: target))
        }
        authBlocked.remove(target.id)
        passwordPromptTarget = nil
        passwordPromptError = nil
        Task { await refresh() }
    }

    func cancelPasswordPrompt() {
        // Stay authBlocked: the timer won't hammer the host, the error banner
        // keeps a "비밀번호 입력" affordance for whenever the user is ready.
        passwordPromptTarget = nil
        passwordPromptError = nil
    }

    func reopenPasswordPrompt() {
        guard !selectedTarget.isLocal else { return }
        passwordPromptError = nil
        passwordPromptTarget = selectedTarget
    }

    // MARK: - kqueue exit watchers (local, push-based)

    /// Watch every displayed local PID with kqueue NOTE_EXIT. A dev server
    /// dying (or being killed outside Porter) updates the UI immediately,
    /// independent of the poll interval.
    private func syncProcessWatchers(pids: Set<Int>) {
        for (pid, source) in processWatchers where !pids.contains(pid) {
            source.cancel()
            processWatchers.removeValue(forKey: pid)
        }
        for pid in pids where processWatchers[pid] == nil {
            let source = DispatchSource.makeProcessSource(
                identifier: pid_t(pid), eventMask: .exit, queue: .main
            )
            source.setEventHandler { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.processWatchers[pid]?.cancel()
                    self.processWatchers.removeValue(forKey: pid)
                    let name = self.ports.first { $0.pid == pid }?.command ?? "?"
                    self.log(.info, "종료 감지: \(name) (PID \(pid)) — 목록 갱신")
                    if !self.isScanning { await self.refresh() }
                }
            }
            source.activate()
            processWatchers[pid] = source
        }
    }

    private func clearProcessWatchers() {
        processWatchers.values.forEach { $0.cancel() }
        processWatchers.removeAll()
    }

    // MARK: - Detail

    func selectPort(_ entry: PortEntry?) {
        selectedPortID = entry?.id
        detail = nil
        logPreview = nil
        logPreviewFile = nil
        stopLogStream()
        guard let entry else { return }
        if isDemo {
            detail = DemoData.detail(for: entry)
            return
        }
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
        stopLogStream()
        logPreviewFile = file
        logPreview = nil
        if isDemo {
            logPreview = DemoData.logTail
            return
        }
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

    // MARK: - Live log streaming (tail -F)

    func startLogStream(file: String) {
        stopLogStream()
        logPreview = nil
        logPreviewFile = file
        if isDemo {
            // Demo: replay the canned tail as if it were streaming.
            liveLogLines = DemoData.logTail.components(separatedBy: "\n")
            streamingFile = file
            isStreamingLog = true
            return
        }
        liveLogLines = []
        streamingFile = file
        isStreamingLog = true

        let script = "tail -n 60 -F \(Scanner.shellQuote(file)) 2>/dev/null"
        let stream = LogStream(target: selectedTarget, script: script)
        stream.onLine = { [weak self] line in
            guard let self, self.streamingFile == file else { return }
            self.liveLogLines.append(line)
            if self.liveLogLines.count > 500 {
                self.liveLogLines.removeFirst(self.liveLogLines.count - 500)
            }
        }
        stream.onEnd = { [weak self] error in
            guard let self, self.streamingFile == file else { return }
            self.isStreamingLog = false
            if let error { self.log(.warning, "라이브 로그 중단: \(error)") }
        }
        logStream = stream
        stream.start()
        log(.info, "라이브 로그 시작: \((file as NSString).lastPathComponent)")
    }

    func stopLogStream() {
        logStream?.stop()
        logStream = nil
        if isStreamingLog { log(.info, "라이브 로그 중지") }
        isStreamingLog = false
        streamingFile = nil
    }

    // MARK: - Control (F4)

    /// SIGTERM, verify, report. Returns true when the process is gone.
    @discardableResult
    func kill(_ entry: PortEntry, force: Bool) async -> Bool {
        // Demo PIDs are fictional but could collide with real ones — never signal.
        guard !isDemo else {
            log(.info, "(demo) 종료: \(entry.command) (PID \(entry.pid))")
            return true
        }
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
    /// `logPath` (Porter-managed, $HOME-relative) makes the new process's
    /// output live-streamable; nil discards output as before.
    func restart(_ entry: PortEntry, command: String, cwd: String, logPath: String?) async {
        guard !isDemo else {
            log(.info, "(demo) 재시작: \(entry.command) :\(entry.port)")
            return
        }
        let target = selectedTarget
        isActing = true
        defer { isActing = false }
        do {
            let runner = Runners.runner(for: target)
            _ = try await runner.run(Scanner.killScript(pid: entry.pid, force: false))
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            let script = Scanner.restartScript(command: command, cwd: cwd, logPath: logPath)
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

    /// Row-level entry point for "restart / change port": ensures the detail
    /// (command, cwd) is loaded before the sheet opens.
    func requestRestart(_ entry: PortEntry) {
        if selectedPortID != entry.id { selectPort(entry) }
        Task {
            for _ in 0..<30 where detail?.pid != entry.pid {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard detail?.cwd != nil else {
                log(.warning, "\(entry.command) (PID \(entry.pid)): 작업 디렉토리를 알 수 없어 재시작할 수 없습니다")
                return
            }
            restartCandidate = entry
        }
    }

    // MARK: - Activity feed

    func log(_ kind: ActivityEvent.Kind, _ message: String) {
        events.append(ActivityEvent(date: Date(), kind: kind,
                                    targetName: selectedTarget.name, message: message))
        if events.count > 300 { events.removeFirst(events.count - 300) }
    }
}
