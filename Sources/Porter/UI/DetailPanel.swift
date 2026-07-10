import SwiftUI

/// Right inspector: process detail + safe controls (F3, F4).
struct DetailPanel: View {
    @EnvironmentObject var state: AppState
    let entry: PortEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if state.isLoadingDetail {
                        HStack {
                            Spacer()
                            ProgressView().controlSize(.small)
                            Spacer()
                        }
                        .padding(.top, 30)
                    } else if let detail = state.detail {
                        if detail.isProtected {
                            protectedBanner
                        }
                        if let project = state.projects[entry.pid] {
                            projectCard(project)
                        }
                        openSection
                        statGrid(detail)
                        CopyableValue(label: L("Command"), value: detail.fullCommand)
                        if let cwd = detail.cwd {
                            CopyableValue(label: L("Working Directory"), value: cwd)
                        }
                        logSection(detail)
                    } else {
                        Text(L("프로세스 정보를 가져올 수 없습니다.\n이미 종료되었을 수 있습니다."))
                            .font(Theme.ui(12))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 30)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(14)
            }

            Divider().overlay(Theme.border)
            controls
        }
        .frame(width: 330)
        .background(Theme.surface)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: ProcessIcon.symbol(for: entry.command))
                .font(.system(size: 15))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.command)
                    .font(Theme.ui(14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(":\(String(entry.port))")
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.green)
                    if let label = entry.devLabel {
                        Chip(text: label, color: Theme.purple)
                    }
                }
            }
            Spacer()
            Button {
                state.selectPort(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var protectedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(Theme.amber)
            Text(L("시스템/보호 프로세스로 보입니다. 종료 시 각별히 주의하세요."))
                .font(Theme.ui(11))
                .foregroundStyle(Theme.amber)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amber.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
    }

    // MARK: Project identity + shortcuts

    private func projectCard(_ project: ProjectInfo) -> some View {
        let color = Theme.color(for: project.category)
        return HStack(spacing: 10) {
            Image(systemName: project.category.symbol)
                .font(.system(size: 15))
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name ?? entry.command)
                    .font(Theme.ui(13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let framework = project.framework {
                        Chip(text: framework, color: color)
                    }
                    Text(project.category.label)
                        .font(Theme.ui(9.5, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .kerning(0.5)
                }
            }
            Spacer()
        }
        .padding(11)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder
    private var openSection: some View {
        let urls = state.urls(for: entry)
        if !urls.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("OPEN"))
                    .font(Theme.ui(10, weight: .semibold))
                    .foregroundStyle(Theme.textFaint)
                ForEach(urls) { portURL in
                    Button {
                        state.open(portURL)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: portURL.label == "Tailscale"
                                  ? "shield.checkered" : "safari")
                                .font(.system(size: 11))
                            Text(portURL.url.absoluteString)
                                .font(Theme.mono(11))
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(portURL.label == "Tailscale"
                          ? L("Tailscale 네트워크의 다른 기기에서도 접근 가능")
                          : L("브라우저에서 열기"))
                }
            }
        } else if !state.selectedTarget.isLocal && entry.isLoopbackOnly {
            HStack(spacing: 7) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                Text(L("루프백 전용 바인드 — 원격에서 직접 접근할 수 없습니다"))
                    .font(Theme.ui(11))
            }
            .foregroundStyle(Theme.textFaint)
        }
    }

    // MARK: Stats

    private func statGrid(_ detail: ProcessDetail) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                statCell("PID", String(detail.pid))
                statCell("PPID", detail.ppid.map(String.init) ?? "—")
                statCell("USER", detail.user)
                statCell("CPU", detail.cpu.map { String(format: "%.1f%%", $0) } ?? "—")
                statCell("MEM", detail.mem.map { String(format: "%.1f%%", $0) } ?? "—")
                statCell("BIND", entry.address)
            }
            statCell("STARTED", detail.started.isEmpty ? "—" : detail.started)
        }
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.ui(9, weight: .bold))
                .foregroundStyle(Theme.textFaint)
                .kerning(0.5)
            Text(value)
                .font(Theme.mono(11.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: Logs (F3.4)

    @ViewBuilder
    private func logSection(_ detail: ProcessDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("LOG FILES"))
                .font(Theme.ui(10, weight: .semibold))
                .foregroundStyle(Theme.textFaint)

            if detail.logFiles.isEmpty {
                Text(L("열려 있는 로그 파일이 감지되지 않았습니다.\nPorter로 Restart하면 출력이 ~/.porter/logs에 기록되어 라이브 로그를 볼 수 있습니다."))
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.textFaint)
            } else {
                ForEach(detail.logFiles, id: \.self) { file in
                    HStack(spacing: 6) {
                        Button {
                            state.loadLogPreview(file: file)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 10))
                                Text((file as NSString).lastPathComponent)
                                    .font(Theme.mono(11))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .foregroundStyle(state.logPreviewFile == file ? Theme.accent : Theme.textSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(file)

                        // Live follow (tail -F) toggle
                        Button {
                            if state.isStreamingLog && state.streamingFile == file {
                                state.stopLogStream()
                            } else {
                                state.startLogStream(file: file)
                            }
                        } label: {
                            Image(systemName: state.isStreamingLog && state.streamingFile == file
                                  ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(state.isStreamingLog && state.streamingFile == file
                                                 ? Theme.green : Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help(state.isStreamingLog && state.streamingFile == file
                              ? L("라이브 로그 중지") : L("라이브 로그 (tail -F)"))
                    }
                }

                if state.isStreamingLog || state.streamingFile != nil {
                    liveLogView
                } else if state.logPreviewFile != nil {
                    ScrollView {
                        Text(state.logPreview ?? L("불러오는 중…"))
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 150)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                }
            }
        }
    }

    /// Auto-scrolling live tail with a status line.
    private var liveLogView: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                StatusDot(color: state.isStreamingLog ? Theme.green : Theme.textFaint, size: 6)
                Text(state.isStreamingLog ? L("LIVE") : L("중지됨"))
                    .font(Theme.ui(9, weight: .bold))
                    .foregroundStyle(state.isStreamingLog ? Theme.green : Theme.textFaint)
                    .kerning(0.8)
                Text(L("\(state.liveLogLines.count)줄"))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textFaint)
                Spacer()
                Button(L("지우기")) { state.liveLogLines = [] }
                    .buttonStyle(.plain)
                    .font(Theme.ui(9.5))
                    .foregroundStyle(Theme.textFaint)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(state.liveLogLines.enumerated()), id: \.offset) { index, line in
                            Text(line.isEmpty ? " " : line)
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 190)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(state.isStreamingLog ? Theme.green.opacity(0.35) : Theme.border, lineWidth: 1))
                .onChange(of: state.liveLogLines.count) { _, count in
                    if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: Controls (F4)

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                state.killCandidate = entry
            } label: {
                Label(L("Kill"), systemImage: "stop.fill")
            }
            .buttonStyle(PorterButtonStyle(tint: Theme.red))
            .disabled(state.isActing || entry.pid <= 0)

            Button {
                state.restartCandidate = entry
            } label: {
                Label(L("Restart"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(PorterButtonStyle(tint: Theme.accent))
            .disabled(state.isActing || state.detail?.cwd == nil)
            .help(state.detail?.cwd == nil ? L("작업 디렉토리를 알 수 없어 재시작할 수 없습니다") : L("kill 후 같은 명령어로 재시작"))

            Spacer()
            if state.isActing {
                ProgressView().controlSize(.small)
            }
        }
        .padding(12)
    }
}
