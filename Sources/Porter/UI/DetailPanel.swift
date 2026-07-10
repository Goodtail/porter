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
                        statGrid(detail)
                        CopyableValue(label: "Command", value: detail.fullCommand)
                        if let cwd = detail.cwd {
                            CopyableValue(label: "Working Directory", value: cwd)
                        }
                        logSection(detail)
                    } else {
                        Text("프로세스 정보를 가져올 수 없습니다.\n이미 종료되었을 수 있습니다.")
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
            Text("시스템/보호 프로세스로 보입니다. 종료 시 각별히 주의하세요.")
                .font(Theme.ui(11))
                .foregroundStyle(Theme.amber)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amber.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
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
            Text("LOG FILES")
                .font(Theme.ui(10, weight: .semibold))
                .foregroundStyle(Theme.textFaint)

            if detail.logFiles.isEmpty {
                Text("열려 있는 로그 파일이 감지되지 않았습니다")
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.textFaint)
            } else {
                ForEach(detail.logFiles, id: \.self) { file in
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
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(state.logPreviewFile == file ? Theme.accent : Theme.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(file)
                }

                if state.logPreviewFile != nil {
                    ScrollView {
                        Text(state.logPreview ?? "불러오는 중…")
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

    // MARK: Controls (F4)

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                state.killCandidate = entry
            } label: {
                Label("Kill", systemImage: "stop.fill")
            }
            .buttonStyle(PorterButtonStyle(tint: Theme.red))
            .disabled(state.isActing || entry.pid <= 0)

            Button {
                state.restartCandidate = entry
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PorterButtonStyle(tint: Theme.accent))
            .disabled(state.isActing || state.detail?.cwd == nil)
            .help(state.detail?.cwd == nil ? "작업 디렉토리를 알 수 없어 재시작할 수 없습니다" : "kill 후 같은 명령어로 재시작")

            Spacer()
            if state.isActing {
                ProgressView().controlSize(.small)
            }
        }
        .padding(12)
    }
}
