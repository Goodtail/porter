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

    // MARK: Run history
    @Published var history: [HistoryEntry] = []
    @Published var showHistory = false
    @Published var relaunchCandidate: HistoryEntry?   // opens RelaunchSheet

    // MARK: Favicons ("host:port" → image, fetched from the live service)
    @Published var favicons: [String: NSImage] = [:]
    private var faviconAttempted: Set<String> = []

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
    enum FeedTab { case activity, history }
    @Published var feedTab: FeedTab = .activity
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
            favicons = DemoData.favicons
            history = DemoData.history
            return
        }
        var all: [Target] = [.local]
        all += SSHConfigParser.targetsFromDefaultConfig()
        all += TargetStore.load()
        targets = all
        history = HistoryStore.load()
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
        log(.info, L("SSH 타깃 추가: \(label)"))
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
            if changed { log(.info, L("스캔: LISTEN 포트 \(newPorts.count)개")) }
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
            Task {
                await fetchProjectsIfNeeded()
                fetchFaviconsIfNeeded()
            }
            if !tailscaleProbed.contains(target.id) {
                tailscaleProbed.insert(target.id)
                Task { await probeTailscale(target) }
            }
        } catch {
            guard generation == scanGeneration, target.id == selectedTargetID else { return }
            let message = error.localizedDescription
            scanError = message
            connectionStates[target.id] = .failed(message)
            log(.error, L("스캔 실패: \(message)"))

            // Auth failure on a target whose server accepts passwords → prompt (F1.5+).
            if !target.isLocal, SSHAuth.canRetryWithPassword(message) {
                let hadPassword = SSHPasswordVault.shared.password(for: target.id) != nil
                let firstFailure = !authBlocked.contains(target.id)
                authBlocked.insert(target.id)
                if passwordPromptTarget == nil, firstFailure {
                    passwordPromptError = hadPassword
                        ? L("인증에 실패했습니다 — 비밀번호를 다시 확인하세요.")
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
                log(.info, L("Tailscale 감지: \(ip)"))
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
        log(.info, L("브라우저 열기: \(portURL.url.absoluteString)"))
    }

    /// Favicons come from the live service itself (/favicon.ico or the
    /// homepage's <link rel=icon>), so local and remote behave identically.
    private func fetchFaviconsIfNeeded() {
        guard !isDemo else { return }
        for entry in ports {
            guard let primary = urls(for: entry).first else { continue }
            let key = FaviconFetcher.key(primary.url)
            guard !faviconAttempted.contains(key) else { continue }
            faviconAttempted.insert(key)
            Task { [weak self] in
                if let icon = await FaviconFetcher.fetch(base: primary.url) {
                    self?.favicons[key] = icon
                }
            }
        }
    }

    // MARK: - Run history (kill 후에도 명령어·디렉토리를 잃지 않기)

    private func recordHistory(action: HistoryEntry.Action, entry: PortEntry,
                               fullCommand: String, cwd: String) {
        let record = HistoryEntry(
            id: UUID(), date: Date(), action: action,
            targetID: selectedTargetID, targetName: selectedTarget.name,
            port: entry.port, command: entry.command,
            fullCommand: fullCommand, cwd: cwd,
            projectName: projects[entry.pid]?.name,
            framework: projects[entry.pid]?.framework,
            devCommand: projects[entry.pid]?.devCommand
        )
        history.insert(record, at: 0)
        if history.count > HistoryStore.cap { history.removeLast(history.count - HistoryStore.cap) }
        if !isDemo { HistoryStore.save(history) }
    }

    func deleteHistory(_ id: HistoryEntry.ID) {
        history.removeAll { $0.id == id }
        if !isDemo { HistoryStore.save(history) }
    }

    func clearHistory() {
        history = []
        if !isDemo { HistoryStore.save(history) }
    }

    /// Relaunch a historical process on its original target: same command,
    /// same cwd, output captured to a Porter-managed log.
    func relaunch(_ record: HistoryEntry, command: String, cwd: String, port: Int) async {
        guard !isDemo else {
            log(.info, L("(demo) 재실행: \(record.command) :\(port)"))
            return
        }
        guard let target = targets.first(where: { $0.id == record.targetID }) else {
            log(.error, L("재실행 실패: 타깃 '\(record.targetName)'을 찾을 수 없습니다"))
            return
        }
        isActing = true
        defer { isActing = false }

        let logPath = PortRewriter.managedLogPath(name: record.projectName,
                                                  command: record.command, port: port)
        let script = Scanner.restartScript(command: command, cwd: cwd, logPath: logPath)
        do {
            let result = try await Runners.runner(for: target).run(script)
            switch Scanner.parseRestartResult(result.stdout) {
            case .started(let newPid):
                log(.success, L("재실행: \(record.command) :\(port) on \(target.name) → 새 PID \(newPid)"))
                history.removeAll { $0.id == record.id }
                history.insert(HistoryEntry(id: UUID(), date: Date(), action: .relaunch,
                                            targetID: record.targetID, targetName: record.targetName,
                                            port: port, command: record.command,
                                            fullCommand: command, cwd: cwd,
                                            projectName: record.projectName,
                                            framework: record.framework,
                                            devCommand: record.devCommand), at: 0)
                HistoryStore.save(history)
            case .diedInstantly(let tail):
                let tailText = tail.isEmpty ? L("로그 없음") : tail
                log(.error, L("재실행 직후 종료됨 — \(tailText)"))
            case .badDirectory:
                log(.error, L("재실행 실패: 디렉토리가 없습니다 — \(cwd)"))
            case nil:
                throw CommandError.failed(exitCode: result.exitCode, stderr: result.stderr)
            }
        } catch {
            log(.error, L("재실행 실패 (\(record.command)): \(error.localizedDescription)"))
        }
        if target.id == selectedTargetID {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refresh()
        }
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
                    self.log(.info, L("종료 감지: \(name) (PID \(pid)) — 목록 갱신"))
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
            log(.error, L("상세 조회 실패 (PID \(entry.pid)): \(error.localizedDescription)"))
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
                logPreview = result.stdout.isEmpty ? L("(비어 있음)") : result.stdout
            } catch {
                logPreview = L("로그를 읽을 수 없습니다: \(error.localizedDescription)")
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
            if let error {
                let detail = String(describing: error)
                self.log(.warning, L("라이브 로그 중단: \(detail)"))
            }
        }
        logStream = stream
        stream.start()
        log(.info, L("라이브 로그 시작: \((file as NSString).lastPathComponent)"))
    }

    func stopLogStream() {
        logStream?.stop()
        logStream = nil
        if isStreamingLog { log(.info, L("라이브 로그 중지")) }
        isStreamingLog = false
        streamingFile = nil
    }

    // MARK: - Control (F4)

    /// SIGTERM, verify, report. Returns true when the process is gone.
    @discardableResult
    func kill(_ entry: PortEntry, force: Bool) async -> Bool {
        // Demo PIDs are fictional but could collide with real ones — never signal.
        guard !isDemo else {
            log(.info, L("(demo) 종료: \(entry.command) (PID \(entry.pid))"))
            return true
        }
        let target = selectedTarget
        isActing = true
        defer { isActing = false }
        do {
            let runner = Runners.runner(for: target)

            // Snapshot command/cwd BEFORE the process dies — this is what makes
            // the history relaunchable (F-history).
            var snapshot: ProcessDetail? = (detail?.pid == entry.pid) ? detail : nil
            if snapshot == nil,
               let fetched = try? await runner.run(Scanner.detailScript(pid: entry.pid)) {
                snapshot = Scanner.parseDetail(fetched.stdout, pid: entry.pid,
                                               fallbackUser: entry.user)
            }

            let result = try await runner.run(Scanner.killScript(pid: entry.pid, force: force))
            if !result.succeeded {
                throw CommandError.failed(exitCode: result.exitCode, stderr: result.stderr)
            }
            // Give SIGTERM a moment, then verify.
            try? await Task.sleep(nanoseconds: force ? 300_000_000 : 1_200_000_000)
            let alive = try await runner.run(Scanner.aliveScript(pid: entry.pid))
            let dead = alive.stdout.contains("DEAD")
            if dead {
                let action = force ? L("강제 종료") : L("종료")
                log(.success, L("\(action): \(entry.command) (PID \(entry.pid), :\(entry.port))"))
                if let snapshot, let cwd = snapshot.cwd {
                    recordHistory(action: .kill, entry: entry,
                                  fullCommand: snapshot.fullCommand, cwd: cwd)
                }
            } else {
                log(.warning, L("\(entry.command) (PID \(entry.pid))가 SIGTERM 후에도 살아있습니다 — Force Kill을 사용하세요"))
            }
            await refresh()
            return dead
        } catch {
            log(.error, L("종료 실패 (PID \(entry.pid)): \(error.localizedDescription)"))
            await refresh()
            return false
        }
    }

    /// Kill + relaunch with the recorded command in the recorded cwd.
    /// `logPath` (Porter-managed, $HOME-relative) makes the new process's
    /// output live-streamable; nil discards output as before.
    func restart(_ entry: PortEntry, command: String, cwd: String, logPath: String?) async {
        guard !isDemo else {
            log(.info, L("(demo) 재시작: \(entry.command) :\(entry.port)"))
            return
        }
        let target = selectedTarget
        isActing = true
        defer { isActing = false }
        recordHistory(action: .restart, entry: entry, fullCommand: command, cwd: cwd)
        do {
            let runner = Runners.runner(for: target)
            _ = try await runner.run(Scanner.killScript(pid: entry.pid, force: false))
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            let script = Scanner.restartScript(command: command, cwd: cwd, logPath: logPath)
            let result = try await runner.run(script)
            switch Scanner.parseRestartResult(result.stdout) {
            case .started(let newPid):
                log(.success, L("재시작: \(entry.command) :\(entry.port) → 새 PID \(newPid)"))
            case .diedInstantly(let tail):
                let tailText = tail.isEmpty ? L("로그 없음") : tail
                log(.error, L("재시작 직후 종료됨 — \(tailText)"))
            case .badDirectory:
                log(.error, L("재시작 실패: 디렉토리가 없습니다 — \(cwd)"))
            case nil:
                throw CommandError.failed(exitCode: result.exitCode, stderr: result.stderr)
            }
        } catch {
            log(.error, L("재시작 실패 (\(entry.command)): \(error.localizedDescription)"))
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
                log(.warning, L("\(entry.command) (PID \(entry.pid)): 작업 디렉토리를 알 수 없어 재시작할 수 없습니다"))
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
