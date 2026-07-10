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
