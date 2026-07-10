import SwiftUI

/// Center panel: header bar + listening-port table (F2).
struct PortListView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(Theme.border)

            if let error = state.scanError {
                errorBanner(error)
            }

            if let freePort = state.searchedFreePort {
                freePortBanner(freePort)
            }

            portTable
        }
        .background(Theme.background)
    }

    // MARK: Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(state.selectedTarget.name)
                        .font(Theme.ui(15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    if state.isScanning {
                        ProgressView().controlSize(.small)
                    }
                }
                Text("LISTEN \(state.ports.count)개 포트\(lastScanSuffix)")
                    .font(Theme.ui(10.5))
                    .foregroundStyle(Theme.textFaint)
            }

            Spacer()

            // Search / port-check field (F2.5)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
                TextField("포트 · 프로세스 · PID 검색", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 190)
                if !state.searchText.isEmpty {
                    Button {
                        state.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.border, lineWidth: 1))

            Button {
                withAnimation(.easeOut(duration: 0.12)) { state.groupByCategory.toggle() }
            } label: {
                Image(systemName: state.groupByCategory ? "square.grid.2x2" : "list.bullet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(state.groupByCategory ? Theme.accent : Theme.textSecondary)
            }
            .buttonStyle(PorterButtonStyle())
            .help(state.groupByCategory ? "카테고리 그룹 해제" : "카테고리별로 그룹")

            Toggle(isOn: $state.autoRefresh) {
                Text("Auto")
                    .font(Theme.ui(11, weight: .medium))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .foregroundStyle(Theme.textSecondary)
            .help("5초마다 자동 새로고침")

            Button {
                Task { await state.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(PorterButtonStyle())
            .keyboardShortcut("r", modifiers: .command)
            .help("새로고침 (⌘R)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var lastScanSuffix: String {
        guard let date = state.lastScanDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return " · 마지막 스캔 \(formatter.string(from: date))"
    }

    // MARK: Banners

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.red)
            Text(message)
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            Spacer()
            if !state.selectedTarget.isLocal, SSHAuth.canRetryWithPassword(message) {
                Button {
                    state.reopenPasswordPrompt()
                } label: {
                    Label("비밀번호 입력", systemImage: "key.fill")
                }
                .buttonStyle(PorterButtonStyle(tint: Theme.amber))
            }
            Button("재시도") { Task { await state.refresh() } }
                .buttonStyle(PorterButtonStyle(tint: Theme.red))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.red.opacity(0.08))
    }

    private func freePortBanner(_ port: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.green)
            Text("포트 ")
                .font(Theme.ui(12))
                .foregroundStyle(Theme.textSecondary)
            + Text("\(port)")
                .font(Theme.mono(12, weight: .bold))
                .foregroundStyle(Theme.green)
            + Text("은(는) \(state.selectedTarget.name)에서 비어 있습니다 — 바로 사용 가능")
                .font(Theme.ui(12))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.green.opacity(0.07))
    }

    // MARK: Table

    /// filteredPorts split into ordered category sections (F-sections).
    private var groupedPorts: [(ServiceCategory, [PortEntry])] {
        let groups = Dictionary(grouping: state.filteredPorts) { state.category(for: $0) }
        return ServiceCategory.allCases.compactMap { category in
            groups[category].map { (category, $0) }
        }
    }

    private var portTable: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    if state.filteredPorts.isEmpty && !state.isScanning && state.scanError == nil {
                        emptyState
                    }
                    if state.groupByCategory {
                        ForEach(groupedPorts, id: \.0) { category, entries in
                            sectionHeader(category, count: entries.count)
                            ForEach(entries) { entry in
                                PortRow(entry: entry,
                                        isSelected: state.selectedPortID == entry.id)
                                    .environmentObject(state)
                            }
                        }
                    } else {
                        ForEach(state.filteredPorts) { entry in
                            PortRow(entry: entry,
                                    isSelected: state.selectedPortID == entry.id)
                                .environmentObject(state)
                        }
                    }
                } header: {
                    columnHeader
                }
            }
        }
    }

    private func sectionHeader(_ category: ServiceCategory, count: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: category.symbol)
                .font(.system(size: 9, weight: .bold))
            Text(category.label)
                .font(Theme.ui(10, weight: .bold))
                .kerning(0.8)
            Text("\(count)")
                .font(Theme.mono(9.5))
                .opacity(0.65)
            Rectangle()
                .fill(Theme.color(for: category).opacity(0.16))
                .frame(height: 1)
        }
        .foregroundStyle(Theme.color(for: category))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 5)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("PORT").frame(width: 84, alignment: .leading)
            Text("PROCESS").frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
            Text("PID").frame(width: 70, alignment: .leading)
            Text("USER").frame(width: 90, alignment: .leading)
            Text("BIND").frame(width: 110, alignment: .leading)
            Spacer().frame(width: 70)
        }
        .font(Theme.ui(9.5, weight: .bold))
        .foregroundStyle(Theme.textFaint)
        .kerning(0.6)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Theme.background)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: state.searchText.isEmpty ? "antenna.radiowaves.left.and.right.slash" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textFaint)
            Text(state.searchText.isEmpty
                 ? "LISTEN 중인 TCP 포트가 없습니다"
                 : "검색 결과가 없습니다")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }
}

// MARK: - Row

struct PortRow: View {
    @EnvironmentObject var state: AppState
    let entry: PortEntry
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            state.selectPort(state.selectedPortID == entry.id ? nil : entry)
        } label: {
            HStack(spacing: 0) {
                // PORT
                HStack(spacing: 6) {
                    StatusDot(color: entry.devLabel != nil ? Theme.green : Theme.textFaint, size: 6)
                    Text(String(entry.port))
                        .font(Theme.mono(13, weight: .semibold))
                        .foregroundStyle(entry.devLabel != nil ? Theme.green : Theme.textPrimary)
                }
                .frame(width: 84, alignment: .leading)

                // PROCESS + project identity
                HStack(spacing: 7) {
                    Image(systemName: ProcessIcon.symbol(for: entry.command))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 14)
                    Text(entry.command)
                        .font(Theme.ui(12.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let project = state.projects[entry.pid] {
                        if let framework = project.framework {
                            Chip(text: framework, color: Theme.color(for: project.category))
                        }
                        if let name = project.name {
                            Text(name)
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    } else if let label = entry.devLabel {
                        Chip(text: label, color: Theme.purple)
                    }
                }
                .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)

                // PID
                Text(entry.pid > 0 ? String(entry.pid) : "—")
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 70, alignment: .leading)

                // USER
                Text(entry.user)
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(width: 90, alignment: .leading)

                // BIND
                HStack(spacing: 4) {
                    Text(entry.address)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                    if entry.isLoopbackOnly {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.textFaint)
                            .help("루프백 전용 — 외부에서 접근 불가")
                    }
                }
                .frame(width: 110, alignment: .leading)

                // Hover quick actions: open in browser + kill
                HStack(spacing: 10) {
                    if hovering, let primary = state.urls(for: entry).first {
                        Button {
                            state.open(primary)
                        } label: {
                            Image(systemName: "safari.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .help(primary.url.absoluteString)
                    }
                    if hovering && entry.pid > 0 {
                        Button {
                            state.killCandidate = entry
                        } label: {
                            Image(systemName: "xmark.octagon.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.red)
                        }
                        .buttonStyle(.plain)
                        .help("프로세스 종료")
                    }
                }
                .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("상세 보기") { state.selectPort(entry) }
            let urls = state.urls(for: entry)
            if !urls.isEmpty {
                Divider()
                ForEach(urls) { portURL in
                    Button("열기: \(portURL.url.absoluteString)") { state.open(portURL) }
                }
            }
            Divider()
            Button("재시작 · 포트 변경…") { state.requestRestart(entry) }
            Button("Kill (SIGTERM)", role: .destructive) { state.killCandidate = entry }
        }
    }

    private var rowBackground: some View {
        Rectangle()
            .fill(isSelected ? Theme.surfaceHigh : (hovering ? Theme.surfaceHover : .clear))
    }
}
