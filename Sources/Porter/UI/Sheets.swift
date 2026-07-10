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
                    Text(termFailed ? "프로세스가 아직 살아있습니다" : "프로세스를 종료할까요?")
                        .font(Theme.ui(15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(termFailed
                         ? "SIGTERM에 응답하지 않았습니다. SIGKILL로 강제 종료할 수 있습니다."
                         : "확인 후 SIGTERM을 보냅니다. 저장하지 않은 작업은 사라질 수 있습니다.")
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // What exactly is being killed — the anti-"wrong PID" guard.
            VStack(alignment: .leading, spacing: 6) {
                factRow("타깃", state.selectedTarget.name + (state.selectedTarget.isLocal ? "" : " (\(state.selectedTarget.subtitle))"))
                factRow("프로세스", "\(entry.command)  ·  PID \(entry.pid)")
                factRow("포트", ":\(entry.port)  (\(entry.address))")
                if let cmd = state.detail?.fullCommand {
                    factRow("명령어", cmd)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))

            if isProtected {
                Toggle(isOn: $acknowledgedProtected) {
                    Text("시스템/보호 프로세스임을 이해했으며 종료를 원합니다")
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.amber)
                }
                .toggleStyle(.checkbox)
            }

            HStack {
                Spacer()
                Button("취소") { state.killCandidate = nil }
                    .buttonStyle(PorterButtonStyle())
                    .keyboardShortcut(.cancelAction)

                if termFailed {
                    Button {
                        Task {
                            _ = await state.kill(entry, force: true)
                            state.killCandidate = nil
                        }
                    } label: {
                        Label("Force Kill (SIGKILL)", systemImage: "bolt.fill")
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
                        Label("Kill (SIGTERM)", systemImage: "stop.fill")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("프로세스를 재시작할까요?")
                        .font(Theme.ui(15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("SIGTERM으로 종료한 뒤, 아래 디렉토리에서 명령어를 다시 실행합니다 (nohup, 백그라운드).")
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WORKING DIRECTORY")
                        .font(Theme.ui(9.5, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                    TextField("", text: $cwd)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(11.5))
                        .padding(8)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("COMMAND (수정 가능)")
                        .font(Theme.ui(9.5, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                    TextEditor(text: $command)
                        .font(Theme.mono(11.5))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .frame(height: 64)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                }
            }

            HStack {
                Spacer()
                Button("취소") { state.restartCandidate = nil }
                    .buttonStyle(PorterButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button {
                    let cmd = command, dir = cwd
                    Task {
                        await state.restart(entry, command: cmd, cwd: dir)
                        state.restartCandidate = nil
                    }
                } label: {
                    Label("Kill & Restart", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PorterButtonStyle(tint: Theme.accent, prominent: true))
                .disabled(state.isActing || command.trimmingCharacters(in: .whitespaces).isEmpty
                          || cwd.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 480)
        .background(Theme.surface)
        .onAppear {
            command = state.detail?.fullCommand ?? ""
            cwd = state.detail?.cwd ?? ""
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
                    Text("SSH 비밀번호 필요")
                        .font(Theme.ui(15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(target.subtitle) — 키 인증이 거부되어 비밀번호로 접속합니다.")
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

            SecureField("비밀번호", text: $password)
                .textFieldStyle(.plain)
                .font(Theme.mono(13))
                .padding(9)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                .onSubmit(submit)

            Toggle(isOn: $saveToKeychain) {
                Text("macOS Keychain에 저장 (다음 실행에서 자동 사용)")
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            .toggleStyle(.checkbox)

            HStack {
                Text("비밀번호는 ssh에 환경 변수로만 전달되며 디스크에 남지 않습니다.")
                    .font(Theme.ui(10))
                    .foregroundStyle(Theme.textFaint)
                Spacer()
                Button("취소") { state.cancelPasswordPrompt() }
                    .buttonStyle(PorterButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button {
                    submit()
                } label: {
                    Label("연결", systemImage: "bolt.horizontal.fill")
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
                    Text("SSH 타깃 추가")
                        .font(Theme.ui(15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("기존 SSH 키/agent/config를 그대로 사용합니다. 비밀번호는 저장하지 않습니다.")
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            VStack(spacing: 8) {
                field("라벨 (선택)", text: $name, placeholder: "gpu-server")
                field("Host *", text: $host, placeholder: "192.168.1.100 또는 ssh config alias")
                field("User (선택)", text: $user, placeholder: "ubuntu")
                field("Port (선택)", text: $port, placeholder: "22")
            }

            HStack {
                Spacer()
                Button("취소") { state.showAddTarget = false }
                    .buttonStyle(PorterButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("추가") {
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
