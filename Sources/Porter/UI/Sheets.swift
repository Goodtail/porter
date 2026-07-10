import SwiftUI

// MARK: - Kill confirmation (F4.1, F4.2, F4.4)

/// Custom confirmation sheet that always shows exactly what will die, where.
struct KillConfirmSheet: View {
    @EnvironmentObject var state: AppState
    let entry: PortEntry

    @State private var acknowledgedProtected = false
    @State private var termFailed = false

    private var isProtected: Bool { state.detail?.isProtected ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: termFailed ? "exclamationmark.octagon.fill" : "stop.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(termFailed ? L("프로세스가 아직 살아있습니다") : L("프로세스를 종료할까요?"))
                        .font(Theme.ui(15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(termFailed
                         ? L("SIGTERM에 응답하지 않았습니다. SIGKILL로 강제 종료할 수 있습니다.")
                         : L("확인 후 SIGTERM을 보냅니다. 저장하지 않은 작업은 사라질 수 있습니다."))
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // What exactly is being killed — the anti-"wrong PID" guard.
            VStack(alignment: .leading, spacing: 6) {
                factRow(L("타깃"), state.selectedTarget.name + (state.selectedTarget.isLocal ? "" : " (\(state.selectedTarget.subtitle))"))
                factRow(L("프로세스"), "\(entry.command)  ·  PID \(entry.pid)")
                factRow(L("포트"), ":\(entry.port)  (\(entry.address))")
                if let cmd = state.detail?.fullCommand {
                    factRow(L("명령어"), cmd)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))

            if isProtected {
                Toggle(isOn: $acknowledgedProtected) {
                    Text(L("시스템/보호 프로세스임을 이해했으며 종료를 원합니다"))
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.amber)
                }
                .toggleStyle(.checkbox)
            }

            HStack {
                Spacer()
                Button(L("취소")) { state.killCandidate = nil }
                    .buttonStyle(PorterButtonStyle())
                    .keyboardShortcut(.cancelAction)

                if termFailed {
                    Button {
                        Task {
                            _ = await state.kill(entry, force: true)
                            state.killCandidate = nil
                        }
                    } label: {
                        Label(L("Force Kill (SIGKILL)"), systemImage: "bolt.fill")
                    }
                    .buttonStyle(PorterButtonStyle(tint: Theme.red, prominent: true))
                    .disabled(state.isActing)
                } else {
                    Button {
                        Task {
                            let dead = await state.kill(entry, force: false)
                            if dead {
                                state.killCandidate = nil
                            } else {
                                termFailed = true
                            }
                        }
                    } label: {
                        Label(L("Kill (SIGTERM)"), systemImage: "stop.fill")
                    }
                    .buttonStyle(PorterButtonStyle(tint: Theme.red, prominent: true))
                    .disabled(state.isActing || (isProtected && !acknowledgedProtected))
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(Theme.surface)
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(Theme.ui(10.5, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Restart confirmation (F4.3)

struct RestartConfirmSheet: View {
    @EnvironmentObject var state: AppState
    let entry: PortEntry

    @State private var command: String = ""
    @State private var cwd: String = ""
    @State private var portText: String = ""
    @State private var captureLog = true
    /// The untouched original — port rewrites always re-derive from this.
    @State private var baseCommand: String = ""
    @State private var substitutedDevScript = false

    private var newPort: Int? { Int(portText.trimmingCharacters(in: .whitespaces)) }
    private var portChanged: Bool { newPort != nil && newPort != entry.port }
    private var portValid: Bool { newPort.map { (1...65535).contains($0) } ?? false }

    private var logPath: String? {
        guard captureLog else { return nil }
        return PortRewriter.managedLogPath(
            name: state.projects[entry.pid]?.name,
            command: entry.command,
            port: newPort ?? entry.port
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(portChanged ? L("포트를 옮겨 재시작할까요?") : L("프로세스를 재시작할까요?"))
                        .font(Theme.ui(15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("SIGTERM으로 종료한 뒤, 아래 디렉토리에서 명령어를 다시 실행합니다 (nohup, 백그라운드)."))
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PORT")
                            .font(Theme.ui(9.5, weight: .bold))
                            .foregroundStyle(Theme.textFaint)
                        TextField("\(entry.port)", text: $portText)
                            .textFieldStyle(.plain)
                            .font(Theme.mono(12, weight: .semibold))
                            .foregroundStyle(portChanged ? Theme.green : Theme.textPrimary)
                            .padding(8)
                            .frame(width: 90)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(portChanged ? Theme.green.opacity(0.5) : Theme.border, lineWidth: 1))
                            .onChange(of: portText) { _, _ in
                                // Re-derive from the original so edits don't stack.
                                if let port = newPort, portValid {
                                    command = PortRewriter.rewrite(command: baseCommand,
                                                                   from: entry.port, to: port)
                                } else {
                                    command = baseCommand
                                }
                            }
                        if portChanged {
                            Text(":\(entry.port) → :\(portText)")
                                .font(Theme.mono(9.5))
                                .foregroundStyle(Theme.green)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("WORKING DIRECTORY"))
                            .font(Theme.ui(9.5, weight: .bold))
                            .foregroundStyle(Theme.textFaint)
                        TextField("", text: $cwd)
                            .textFieldStyle(.plain)
                            .font(Theme.mono(11.5))
                            .padding(8)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("COMMAND (수정 가능)"))
                        .font(Theme.ui(9.5, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                    TextEditor(text: $command)
                        .font(Theme.mono(11.5))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .frame(height: 64)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                    if substitutedDevScript {
                        HStack(spacing: 5) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 9))
                            Text(L("ps의 명령어가 실행 불가능한 프로세스 타이틀이라 package.json 스크립트로 대체했습니다"))
                                .font(Theme.ui(10))
                        }
                        .foregroundStyle(Theme.purple)
                    }
                }
                Toggle(isOn: $captureLog) {
                    Text(L("출력을 Porter 로그로 기록 — 재시작 후 라이브 로그 사용 가능 (~/.porter/logs)"))
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.checkbox)
            }

            HStack {
                Spacer()
                Button(L("취소")) { state.restartCandidate = nil }
                    .buttonStyle(PorterButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button {
                    let cmd = command, dir = cwd, log = logPath
                    Task {
                        await state.restart(entry, command: cmd, cwd: dir, logPath: log)
                        state.restartCandidate = nil
                    }
                } label: {
                    Label(portChanged ? L("Kill & Restart on :\(portText)") : L("Kill & Restart"),
                          systemImage: "arrow.clockwise")
                }
                .buttonStyle(PorterButtonStyle(tint: portChanged ? Theme.green : Theme.accent,
                                               prominent: true))
                .disabled(state.isActing || !portValid
                          || command.trimmingCharacters(in: .whitespaces).isEmpty
                          || cwd.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 520)
        .background(Theme.surface)
        .onAppear {
            let recorded = PortRewriter.sanitize(state.detail?.fullCommand ?? "")
            let devCommand = state.projects[entry.pid]?.devCommand
            // "next-server (v15.3.2)" is a rewritten process title, not a
            // runnable command — substitute the project's dev/start script.
            if ProjectInspector.looksLikeRetitledProcess(recorded), let devCommand {
                baseCommand = devCommand
                substitutedDevScript = true
            } else {
                baseCommand = recorded
            }
            command = baseCommand
            cwd = state.detail?.cwd ?? ""
            portText = String(entry.port)
        }
    }
}

// MARK: - SSH password prompt

/// Shown when a host rejects key auth but accepts passwords. The password is
/// kept in memory for the session; Keychain persistence is opt-in.
struct PasswordPromptSheet: View {
    @EnvironmentObject var state: AppState
    let target: Target

    @State private var password = ""
    @State private var saveToKeychain = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("SSH 비밀번호 필요"))
                        .font(Theme.ui(15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("\(target.subtitle) — 키 인증이 거부되어 비밀번호로 접속합니다."))
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if let error = state.passwordPromptError {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    Text(error)
                        .font(Theme.ui(11.5))
                }
                .foregroundStyle(Theme.red)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
            }

            SecureField(L("비밀번호"), text: $password)
                .textFieldStyle(.plain)
                .font(Theme.mono(13))
                .padding(9)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                .onSubmit(submit)

            Toggle(isOn: $saveToKeychain) {
                Text(L("macOS Keychain에 저장 (다음 실행에서 자동 사용)"))
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            .toggleStyle(.checkbox)

            HStack {
                Text(L("비밀번호는 ssh에 환경 변수로만 전달되며 디스크에 남지 않습니다."))
                    .font(Theme.ui(10))
                    .foregroundStyle(Theme.textFaint)
                Spacer()
                Button(L("취소")) { state.cancelPasswordPrompt() }
                    .buttonStyle(PorterButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button {
                    submit()
                } label: {
                    Label(L("연결"), systemImage: "bolt.horizontal.fill")
                }
                .buttonStyle(PorterButtonStyle(tint: Theme.accent, prominent: true))
                .disabled(password.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(Theme.surface)
    }

    private func submit() {
        guard !password.isEmpty else { return }
        state.submitPassword(password, saveToKeychain: saveToKeychain)
    }
}

// MARK: - Add SSH target (F1.3)

struct AddTargetSheet: View {
    @EnvironmentObject var state: AppState
    @State private var name = ""
    @State private var host = ""
    @State private var user = ""
    @State private var port = ""

    private var valid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
            && (port.isEmpty || Int(port) != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("SSH 타깃 추가"))
                        .font(Theme.ui(15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("기존 SSH 키/agent/config를 그대로 사용합니다. 비밀번호는 저장하지 않습니다."))
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            VStack(spacing: 8) {
                field(L("라벨 (선택)"), text: $name, placeholder: "gpu-server")
                field(L("Host *"), text: $host, placeholder: L("192.168.1.100 또는 ssh config alias"))
                field(L("User (선택)"), text: $user, placeholder: "ubuntu")
                field(L("Port (선택)"), text: $port, placeholder: "22")
            }

            HStack {
                Spacer()
                Button(L("취소")) { state.showAddTarget = false }
                    .buttonStyle(PorterButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(L("추가")) {
                    state.addTarget(
                        name: name.trimmingCharacters(in: .whitespaces),
                        host: host.trimmingCharacters(in: .whitespaces),
                        user: user.trimmingCharacters(in: .whitespaces),
                        port: Int(port)
                    )
                    state.showAddTarget = false
                }
                .buttonStyle(PorterButtonStyle(tint: Theme.accent, prominent: true))
                .disabled(!valid)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 400)
        .background(Theme.surface)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.ui(10.5, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(Theme.mono(12))
                .padding(8)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
        }
    }
}
