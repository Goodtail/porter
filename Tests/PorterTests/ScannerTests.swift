import XCTest
@testable import Porter

final class ScannerTests: XCTestCase {

    // MARK: lsof -F format (macOS + most Linux)

    func testParseLsofOutput() {
        let output = """
        @@LSOF
        p501
        cnode
        u501
        Lcw
        n*:3000
        p777
        cGoogle Chrome H
        u501
        Lcw
        n127.0.0.1:8000
        n[::1]:8000
        """
        let ports = Scanner.parseScan(output)

        // pid 777's IPv4+IPv6 dual bind on :8000 collapses to one row.
        XCTAssertEqual(ports.count, 2)

        let node = ports.first { $0.port == 3000 }
        XCTAssertEqual(node?.pid, 501)
        XCTAssertEqual(node?.command, "node")
        XCTAssertEqual(node?.user, "cw")
        XCTAssertEqual(node?.address, "*")
        XCTAssertEqual(node?.devLabel, "Node · Next.js")

        // Process names with spaces survive (why we use -F, not column parsing).
        let chrome = ports.first { $0.pid == 777 }
        XCTAssertEqual(chrome?.command, "Google Chrome H")
        XCTAssertEqual(chrome?.port, 8000)
        XCTAssertEqual(chrome?.isLoopbackOnly, true)
    }

    func testLsofDedupesSamePortPreferringWildcard() {
        let output = """
        @@LSOF
        p100
        cnode
        u501
        Lcw
        n127.0.0.1:5173
        n*:5173
        """
        let ports = Scanner.parseScan(output)
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].address, "*")
    }

    // MARK: ss fallback (Linux without lsof)

    func testParseSSOutput() {
        let output = """
        @@SS
        LISTEN 0      4096         0.0.0.0:8000       0.0.0.0:*    users:(("uvicorn",pid=1234,fd=23))
        LISTEN 0      511             [::]:3000          [::]:*    users:(("node",pid=5678,fd=19))
        LISTEN 0      128        127.0.0.1:6379       0.0.0.0:*
        @@PS
        1234 ubuntu
        5678 deploy
        """
        let ports = Scanner.parseScan(output)
        XCTAssertEqual(ports.count, 3)

        let uvicorn = ports.first { $0.port == 8000 }
        XCTAssertEqual(uvicorn?.pid, 1234)
        XCTAssertEqual(uvicorn?.command, "uvicorn")
        XCTAssertEqual(uvicorn?.user, "ubuntu")
        XCTAssertEqual(uvicorn?.address, "*")

        let node = ports.first { $0.port == 3000 }
        XCTAssertEqual(node?.pid, 5678)
        XCTAssertEqual(node?.user, "deploy")
        XCTAssertEqual(node?.address, "*")

        // No process column (other user's process, no sudo) → row still shown.
        let redis = ports.first { $0.port == 6379 }
        XCTAssertEqual(redis?.pid, 0)
        XCTAssertEqual(redis?.command, "?")
    }

    // MARK: address:port splitting

    func testSplitAddressPort() {
        XCTAssertEqual(Scanner.splitAddressPort("*:3000")?.0, "*")
        XCTAssertEqual(Scanner.splitAddressPort("*:3000")?.1, 3000)
        XCTAssertEqual(Scanner.splitAddressPort("127.0.0.1:5432")?.0, "127.0.0.1")
        XCTAssertEqual(Scanner.splitAddressPort("[::1]:8080")?.0, "::1")
        XCTAssertEqual(Scanner.splitAddressPort("[::]:80")?.0, "*")
        XCTAssertEqual(Scanner.splitAddressPort("0.0.0.0:443")?.0, "*")
        XCTAssertNil(Scanner.splitAddressPort("no-port-here"))
    }

    // MARK: detail parsing

    func testParseDetail() {
        let marker = "@@PORTER@@"
        let output = """
          400 cw    1.5  0.8
        \(marker)
        Thu Jul 10 09:12:00 2026
        \(marker)
        node /Users/cw/dev/app/server.js --port 3000
        \(marker)
        /Users/cw/dev/app
        \(marker)
        /Users/cw/dev/app/logs/dev.log
        /tmp/server.log
        """
        let detail = Scanner.parseDetail(output, pid: 501, fallbackUser: "cw")
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.ppid, 400)
        XCTAssertEqual(detail?.user, "cw")
        XCTAssertEqual(detail?.cpu, 1.5)
        XCTAssertEqual(detail?.mem, 0.8)
        XCTAssertEqual(detail?.fullCommand, "node /Users/cw/dev/app/server.js --port 3000")
        XCTAssertEqual(detail?.cwd, "/Users/cw/dev/app")
        XCTAssertEqual(detail?.logFiles.count, 2)
        XCTAssertEqual(detail?.isProtected, false)
    }

    func testParseDetailOfDeadProcessReturnsNil() {
        let marker = "@@PORTER@@"
        let output = "\n\(marker)\n\n\(marker)\n\n\(marker)\n\n\(marker)\n"
        XCTAssertNil(Scanner.parseDetail(output, pid: 999, fallbackUser: "cw"))
    }

    func testProtectedHeuristics() {
        var detail = ProcessDetail(pid: 5000, ppid: 1, user: "root", cpu: nil, mem: nil,
                                   started: "", fullCommand: "/opt/thing", cwd: nil, logFiles: [])
        XCTAssertTrue(detail.isProtected, "root-owned is protected")

        detail.user = "cw"
        XCTAssertFalse(detail.isProtected)

        detail.fullCommand = "/System/Library/CoreServices/thing"
        XCTAssertTrue(detail.isProtected, "system path is protected")

        detail.fullCommand = "node server.js"
        XCTAssertFalse(detail.isProtected)
    }

    // MARK: shell quoting

    func testShellQuote() {
        XCTAssertEqual(Scanner.shellQuote("/simple/path"), "'/simple/path'")
        XCTAssertEqual(Scanner.shellQuote("has'quote"), "'has'\\''quote'")
    }

    // MARK: ssh auth failure detection

    func testCanRetryWithPassword() {
        // Server offers password/keyboard-interactive → prompting helps.
        XCTAssertTrue(SSHAuth.canRetryWithPassword(
            "channu-bot@100.67.83.28: Permission denied (publickey,password,keyboard-interactive)."))
        XCTAssertTrue(SSHAuth.canRetryWithPassword(
            "Permission denied (keyboard-interactive)."))
        // Key-only server — a password can't help, don't prompt.
        XCTAssertFalse(SSHAuth.canRetryWithPassword(
            "user@host: Permission denied (publickey)."))
        // Not an auth failure at all.
        XCTAssertFalse(SSHAuth.canRetryWithPassword(
            "ssh: Could not resolve hostname foo: nodename nor servname provided, or not known"))
        XCTAssertFalse(SSHAuth.canRetryWithPassword(
            "ssh: connect to host 10.0.0.5 port 22: Operation timed out"))
    }

    // MARK: project identity detection

    /// Fixture mirrors real output observed on a remote Mac mini:
    /// NestJS API, Next.js app, plain-node relay, plus a manifest-less pid.
    func testProjectInspectorParseAndClassify() {
        let output = """
        @@PID:10709
        @@CWD:/Users/dev/fable/pind-api
        @@PKG
        { "name": "pind-api", "scripts": { "dev": "tsx watch src/main.ts" }, "dependencies": { "@nestjs/common": "^11.1.6" }
        @@PID:11976
        @@CWD:/Users/dev/fable/pind
        @@PKG
        { "name": "pind", "scripts": { "dev": "next dev", "build": "next build" }
        @@PID:18857
        @@CWD:/Users/dev/.orca-remote/relay
        @@PKG
        {"name":"orca-relay","dependencies":{"node-pty":"^1.1.0"}}
        @@PID:405
        @@CWD:/
        """
        let lookup: [Int: PortEntry] = [
            10709: PortEntry(port: 4000, address: "*", proto: "TCP", pid: 10709, command: "node", user: "dev"),
            11976: PortEntry(port: 3000, address: "*", proto: "TCP", pid: 11976, command: "node", user: "dev"),
            18857: PortEntry(port: 6768, address: "*", proto: "TCP", pid: 18857, command: "node", user: "dev"),
            405: PortEntry(port: 5000, address: "*", proto: "TCP", pid: 405, command: "ControlCe", user: "dev"),
        ]
        let projects = ProjectInspector.parse(output, lookup: lookup)

        XCTAssertEqual(projects[10709]?.name, "pind-api")
        XCTAssertEqual(projects[10709]?.framework, "NestJS")
        XCTAssertEqual(projects[10709]?.category, .backend)

        XCTAssertEqual(projects[11976]?.name, "pind")
        XCTAssertEqual(projects[11976]?.framework, "Next.js")
        XCTAssertEqual(projects[11976]?.category, .frontend)

        XCTAssertEqual(projects[18857]?.framework, "Node.js")
        XCTAssertEqual(projects[18857]?.category, .backend)

        // cwd "/" + no manifest → unnamed, classified by command/port fallback.
        XCTAssertNil(projects[405]?.name)
        XCTAssertEqual(projects[405]?.category, .other)
    }

    func testFallbackCategory() {
        XCTAssertEqual(ProjectInspector.fallbackCategory(command: "qdrant", port: 6333), .database)
        XCTAssertEqual(ProjectInspector.fallbackCategory(command: "postgres", port: 5432), .database)
        XCTAssertEqual(ProjectInspector.fallbackCategory(command: "ollama", port: 11434), .ai)
        XCTAssertEqual(ProjectInspector.fallbackCategory(command: "uvicorn", port: 8000), .backend)
        XCTAssertEqual(ProjectInspector.fallbackCategory(command: "rapportd", port: 52942), .other)
    }

    func testPythonProjectDetection() {
        let output = """
        @@PID:77
        @@CWD:/srv/ml-api
        @@PY
        [project]
        name = "ml-api"
        dependencies = ["fastapi>=0.110", "uvicorn"]
        """
        let lookup = [77: PortEntry(port: 8000, address: "*", proto: "TCP", pid: 77, command: "python3", user: "dev")]
        let info = ProjectInspector.parse(output, lookup: lookup)[77]
        XCTAssertEqual(info?.name, "ml-api")
        XCTAssertEqual(info?.framework, "FastAPI")
        XCTAssertEqual(info?.category, .backend)
    }

    // MARK: port rewriting (restart on a different port)

    func testPortRewriter() {
        XCTAssertEqual(
            PortRewriter.rewrite(command: "next dev --port 3000", from: 3000, to: 3001),
            "next dev --port 3001")
        XCTAssertEqual(
            PortRewriter.rewrite(command: "next dev --port=3000", from: 3000, to: 4000),
            "next dev --port=4000")
        XCTAssertEqual(
            PortRewriter.rewrite(command: "next dev -p 3000", from: 3000, to: 3005),
            "next dev -p 3005")
        XCTAssertEqual(
            PortRewriter.rewrite(command: "PORT=3000 node server.js", from: 3000, to: 8080),
            "PORT=8080 node server.js")
        // No recognizable port in the command → PORT env prefix fallback.
        XCTAssertEqual(
            PortRewriter.rewrite(command: "node server.js", from: 3000, to: 3001),
            "PORT=3001 node server.js")
        // Unrelated numbers must not be touched.
        XCTAssertEqual(
            PortRewriter.rewrite(command: "node server.js --workers 3000x --port 3000", from: 3000, to: 3001),
            "node server.js --workers 3000x --port 3001")
        // Same port → unchanged.
        XCTAssertEqual(
            PortRewriter.rewrite(command: "next dev", from: 3000, to: 3000),
            "next dev")
    }

    func testManagedLogPath() {
        XCTAssertEqual(
            PortRewriter.managedLogPath(name: "acme-web", command: "node", port: 3001),
            "$HOME/.porter/logs/acme-web-3001.log")
        XCTAssertEqual(
            PortRewriter.managedLogPath(name: nil, command: "python3.12 -m uvicorn", port: 8000),
            "$HOME/.porter/logs/python3-12-8000.log")
    }

    // MARK: restart script + outcome verification

    func testParseRestartResult() {
        XCTAssertEqual(Scanner.parseRestartResult("PORTER_OK 4242\n"), .started(pid: "4242"))
        XCTAssertEqual(Scanner.parseRestartResult("PORTER_CDFAIL\n"), .badDirectory)
        XCTAssertEqual(Scanner.parseRestartResult("PORTER_DEAD\nzsh: command not found: node\n"),
                       .diedInstantly(logTail: "zsh: command not found: node"))
        XCTAssertNil(Scanner.parseRestartResult("garbage"))
    }

    /// The real script, run through the real local runner: a surviving command
    /// reports PORTER_OK; an instantly-dying one reports PORTER_DEAD with the
    /// log tail; a bad cwd reports PORTER_CDFAIL.
    func testRestartScriptEndToEnd() async throws {
        let dir = FileManager.default.temporaryDirectory.path
        let runner = LocalRunner()

        let ok = try await runner.run(
            Scanner.restartScript(command: "sleep 3", cwd: dir, logPath: nil))
        guard case .started(let pid)? = Scanner.parseRestartResult(ok.stdout) else {
            return XCTFail("expected PORTER_OK, got: \(ok.stdout)")
        }
        _ = try await runner.run("kill -TERM \(pid) 2>/dev/null; true") // cleanup

        let log = dir + "/porter-restart-test.log"
        defer { try? FileManager.default.removeItem(atPath: log) }
        let dead = try await runner.run(
            Scanner.restartScript(command: "definitely-not-a-command-xyz", cwd: dir, logPath: log))
        guard case .diedInstantly(let tail)? = Scanner.parseRestartResult(dead.stdout) else {
            return XCTFail("expected PORTER_DEAD, got: \(dead.stdout)")
        }
        XCTAssertTrue(tail.contains("not found"), "log tail should surface the shell error: \(tail)")

        let badCwd = try await runner.run(
            Scanner.restartScript(command: "true", cwd: "/no/such/dir/porter", logPath: nil))
        XCTAssertEqual(Scanner.parseRestartResult(badCwd.stdout), .badDirectory)
    }

    func testDevCommandDetection() {
        let output = """
        @@PID:1
        @@CWD:/x/web
        @@PKG
        { "name": "web", "scripts": { "dev": "next dev" } }
        @@PNPM
        @@PID:2
        @@CWD:/x/api
        @@PKG
        { "name": "api", "scripts": { "start": "node ." } }
        """
        let lookup = [
            1: PortEntry(port: 3000, address: "*", proto: "TCP", pid: 1, command: "node", user: "u"),
            2: PortEntry(port: 4000, address: "*", proto: "TCP", pid: 2, command: "node", user: "u"),
        ]
        let projects = ProjectInspector.parse(output, lookup: lookup)
        XCTAssertEqual(projects[1]?.devCommand, "pnpm dev")
        XCTAssertNil(projects[2]?.devCommand, "no dev script → no dev command")
        XCTAssertTrue(ProjectInspector.looksLikeRetitledProcess("next-server (v15.3.2)"))
        XCTAssertFalse(ProjectInspector.looksLikeRetitledProcess("node /x/server.js --port 3000"))
    }

    func testHistoryEntryDecodesLegacyJSONWithoutDevCommand() throws {
        let legacy = """
        [{"id":"\(UUID().uuidString)","date":700000000,"action":"kill","targetID":"local",
        "targetName":"My Mac","port":3000,"command":"node","fullCommand":"node x.js",
        "cwd":"/tmp","projectName":null,"framework":null}]
        """
        let decoded = try JSONDecoder().decode([HistoryEntry].self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertNil(decoded[0].devCommand)
    }

    // MARK: history persistence

    func testHistoryStoreRoundtrip() {
        let original = HistoryStore.load()
        defer { HistoryStore.save(original) } // restore user's real history

        let entry = HistoryEntry(id: UUID(), date: Date(), action: .kill,
                                 targetID: "local", targetName: "My Mac", port: 3000,
                                 command: "node", fullCommand: "node server.js",
                                 cwd: "/tmp/proj", projectName: "proj", framework: "Next.js")
        HistoryStore.save([entry])
        let loaded = HistoryStore.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first, entry)

        // Cap: only the newest 50 survive.
        let many = (0..<80).map { index in
            HistoryEntry(id: UUID(), date: Date(), action: .kill,
                         targetID: "local", targetName: "My Mac", port: index,
                         command: "x", fullCommand: "x", cwd: "/", projectName: nil, framework: nil)
        }
        HistoryStore.save(many)
        XCTAssertEqual(HistoryStore.load().count, HistoryStore.cap)
    }

    // MARK: favicon html parsing

    func testFaviconIconPathParsing() {
        XCTAssertEqual(FaviconFetcher.iconPath(fromHTML:
            #"<head><link rel="icon" href="/vite.svg" /></head>"#), "/vite.svg")
        XCTAssertEqual(FaviconFetcher.iconPath(fromHTML:
            #"<link href="/static/fav.png" rel="shortcut icon">"#), "/static/fav.png")
        XCTAssertEqual(FaviconFetcher.iconPath(fromHTML:
            #"<LINK REL="ICON" HREF="favicon-32.png">"#), "favicon-32.png")
        // stylesheet links must not match
        XCTAssertNil(FaviconFetcher.iconPath(fromHTML:
            #"<link rel="stylesheet" href="/main.css">"#))
        XCTAssertNil(FaviconFetcher.iconPath(fromHTML: "<html><body>no links</body></html>"))
    }

    /// End-to-end: a disposable local HTTP server serves favicon.ico; the
    /// fetcher must retrieve and decode it — the exact path the UI uses.
    func testFaviconFetchFromLiveServer() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("porter-favicon-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let onePixelPNG = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        try onePixelPNG.write(to: dir.appendingPathComponent("favicon.ico"))

        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-m", "http.server", "39997", "--bind", "127.0.0.1"]
        server.currentDirectoryURL = dir
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer { server.terminate() }
        try await Task.sleep(nanoseconds: 1_500_000_000)

        let icon = await FaviconFetcher.fetch(base: URL(string: "http://127.0.0.1:39997")!)
        XCTAssertNotNil(icon, "favicon.ico from a live local server must decode")
    }

    // MARK: log streaming

    func testLogStreamDeliversLines() {
        let expectation = expectation(description: "lines")
        var lines: [String] = []
        let stream = LogStream(target: .local,
                               script: "printf 'one\\ntwo\\n'; sleep 0.1; printf 'three\\n'")
        Task { @MainActor in
            stream.onLine = { line in
                lines.append(line)
                if lines.count == 3 { expectation.fulfill() }
            }
            stream.start()
        }
        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(lines, ["one", "two", "three"])
        stream.stop()
    }

    // MARK: tailscale

    func testParseTailscaleIP() {
        XCTAssertEqual(Scanner.parseTailscaleIP("100.67.83.28\n"), "100.67.83.28")
        XCTAssertEqual(Scanner.parseTailscaleIP("100.101.102.103\nfd7a::1\n"), "100.101.102.103")
        XCTAssertNil(Scanner.parseTailscaleIP(""))
        XCTAssertNil(Scanner.parseTailscaleIP("no tailscale here"))
    }

    // MARK: askpass helper + keychain roundtrip

    func testAskpassHelperIsCreatedExecutableAndEchoesPassword() throws {
        let path = SSHAuth.ensureAskpassHelper()
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: path, isDirectory: &isDir))
        XCTAssertFalse(isDir.boolValue)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path))

        // Behave exactly as ssh will invoke it: env var in, password on stdout.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        var env = ProcessInfo.processInfo.environment
        env["PORTER_SSH_PASSWORD"] = "s3cret'with\"quotes"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        XCTAssertEqual(output, "s3cret'with\"quotes\n")
    }

    func testKeychainRoundtrip() {
        let account = "porter-unit-test@example.invalid:22"
        defer { Keychain.delete(account: account) }

        XCTAssertNil(Keychain.load(account: account))
        Keychain.save("first", account: account)
        XCTAssertEqual(Keychain.load(account: account), "first")
        Keychain.save("second", account: account) // overwrite
        XCTAssertEqual(Keychain.load(account: account), "second")
        Keychain.delete(account: account)
        XCTAssertNil(Keychain.load(account: account))
    }

    // MARK: ssh config

    func testSSHConfigParsing() {
        let config = """
        # comment
        Host gpu-server
          HostName 10.0.0.5
          User ubuntu

        Host web1 web2
          User deploy

        Host *
          ServerAliveInterval 60

        Host bastion-?
        """
        let targets = SSHConfigParser.parse(config)
        XCTAssertEqual(targets.map(\.name), ["gpu-server", "web1", "web2"])
        XCTAssertTrue(targets.allSatisfy { $0.fromSSHConfig })
        XCTAssertTrue(targets.allSatisfy { $0.kind == .ssh })
    }
}
