import SwiftUI

// MARK: - History popover (F-history)

/// Every process Porter has killed/restarted, relaunchable in one click —
/// no more hunting down the directory and command after the fact.
struct HistoryPopover: View {
    @EnvironmentObject var state: AppState

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("실행 이력"))
                    .font(Theme.ui(13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(state.history.count)")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textFaint)
                Spacer()
                if !state.history.isEmpty {
                    Button(L("비우기")) { state.clearHistory() }
                        .buttonStyle(.plain)
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().overlay(Theme.border)

            if state.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.textFaint)
                    Text(L("아직 이력이 없습니다.\nPorter로 kill/재시작한 프로세스가 여기 기록되어\n언제든 같은 명령·디렉토리로 다시 실행할 수 있습니다."))
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.history) { record in
                            HistoryRow(record: record)
                                .environmentObject(state)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 400)
        .background(Theme.surface)
    }
}

private struct HistoryRow: View {
    @EnvironmentObject var state: AppState
    let record: HistoryEntry
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.projectName ?? record.command)
                        .font(Theme.ui(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(":\(String(record.port))")
                        .font(Theme.mono(11, weight: .medium))
                        .foregroundStyle(Theme.green)
                    if let framework = record.framework {
                        Chip(text: framework, color: Theme.purple)
                    }
                }
                Text("\(HistoryPopover.timeString(record.date)) · \(record.targetName) · \(record.cwd)")
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }
            Spacer()

            if hovering {
                Button {
                    state.showHistory = false
                    state.relaunchCandidate = record
                } label: {
                    Label(L("재실행"), systemImage: "play.fill")
                        .font(Theme.ui(10.5, weight: .semibold))
                }
                .buttonStyle(PorterButtonStyle(tint: Theme.green))

                Button {
                    state.deleteHistory(record.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                }
                .buttonStyle(.plain)
                .help(L("이력에서 삭제"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(hovering ? Theme.surfaceHover : .clear)
        .onHover { hovering = $0 }
        .help(record.fullCommand)
    }

    private var symbol: String {
        switch record.action {
        case .kill: return "stop.fill"
        case .restart: return "arrow.clockwise"
        case .relaunch: return "play.fill"
        }
    }

    private var color: Color {
        switch record.action {
        case .kill: return Theme.red
        case .restart: return Theme.accent
        case .relaunch: return Theme.green
        }
    }
}

extension HistoryPopover {
    static func timeString(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}

// MARK: - Relaunch sheet

/// Prefilled from a history entry; command/cwd/port editable before running.
struct RelaunchSheet: View {
    @EnvironmentObject var state: AppState
    let record: HistoryEntry

    @State private var command = ""
    @State private var cwd = ""
    @State private var portText = ""
    @State private var baseCommand = ""
    @State private var substitutedDevScript = false

    private var port: Int? { Int(portText.trimmingCharacters(in: .whitespaces)) }
    private var portValid: Bool { port.map { (1...65535).contains($0) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("\(record.projectName ?? record.command) 다시 실행"))
                        .font(Theme.ui(15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("타깃: \(record.targetName) — 출력은 ~/.porter/logs에 기록되어 라이브 로그로 볼 수 있습니다."))
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PORT")
                        .font(Theme.ui(9.5, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                    TextField("", text: $portText)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(12, weight: .semibold))
                        .padding(8)
                        .frame(width: 90)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                        .onChange(of: portText) { _, _ in
                            // Always re-derive from the base so edits never stack.
                            if let newPort = port, portValid {
                                command = PortRewriter.rewrite(command: baseCommand,
                                                               from: record.port, to: newPort)
                            } else {
                                command = baseCommand
                            }
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
                        Text(L("기록된 명령어가 실행 불가능한 프로세스 타이틀이라 package.json 스크립트로 대체했습니다"))
                            .font(Theme.ui(10))
                    }
                    .foregroundStyle(Theme.purple)
                }
            }

            HStack {
                Spacer()
                Button(L("취소")) { state.relaunchCandidate = nil }
                    .buttonStyle(PorterButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button {
                    let cmd = command, dir = cwd, newPort = port ?? record.port
                    Task {
                        await state.relaunch(record, command: cmd, cwd: dir, port: newPort)
                        state.relaunchCandidate = nil
                    }
                } label: {
                    Label(L("실행"), systemImage: "play.fill")
                }
                .buttonStyle(PorterButtonStyle(tint: Theme.green, prominent: true))
                .disabled(state.isActing || !portValid
                          || command.trimmingCharacters(in: .whitespaces).isEmpty
                          || cwd.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 520)
        .background(Theme.surface)
        .onAppear {
            let recorded = PortRewriter.sanitize(record.fullCommand)
            if ProjectInspector.looksLikeRetitledProcess(recorded),
               let devCommand = record.devCommand {
                baseCommand = devCommand
                substitutedDevScript = true
            } else {
                baseCommand = recorded
            }
            command = baseCommand
            cwd = record.cwd
            portText = String(record.port)
        }
    }
}
