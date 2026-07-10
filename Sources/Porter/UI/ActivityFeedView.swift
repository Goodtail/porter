import SwiftUI

/// Bottom strip with two tabs: chronological event log (F5) and the
/// relaunchable run history — both always one glance away.
struct ActivityFeedView: View {
    @EnvironmentObject var state: AppState

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)

            HStack(spacing: 4) {
                tabButton("ACTIVITY", icon: "list.bullet.rectangle",
                          count: state.events.count, tab: .activity)
                tabButton("HISTORY", icon: "clock.arrow.circlepath",
                          count: state.history.count, tab: .history)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { state.feedCollapsed.toggle() }
                } label: {
                    Image(systemName: state.feedCollapsed ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.surface)

            if !state.feedCollapsed {
                Group {
                    switch state.feedTab {
                    case .activity: activityList
                    case .history: historyList
                    }
                }
                .frame(height: 130)
                .background(Theme.surface)
            }
        }
    }

    private func tabButton(_ title: String, icon: String, count: Int,
                           tab: AppState.FeedTab) -> some View {
        let isActive = state.feedTab == tab && !state.feedCollapsed
        return Button {
            state.feedTab = tab
            if state.feedCollapsed { state.feedCollapsed = false }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(Theme.ui(9.5, weight: .bold))
                    .kerning(0.8)
                Text("\(count)")
                    .font(Theme.mono(9.5))
                    .opacity(0.6)
            }
            .foregroundStyle(isActive ? Theme.textPrimary : Theme.textFaint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isActive ? Theme.surfaceHigh : .clear,
                        in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Activity

    private var activityList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(state.events) { event in
                        eventRow(event).id(event.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .onChange(of: state.events.count) { _, _ in
                if let last = state.events.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onAppear {
                if let last = state.events.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func eventRow(_ event: ActivityEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: event.date))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textFaint)
            Text("[\(event.targetName)]")
                .font(Theme.mono(10, weight: .medium))
                .foregroundStyle(Theme.accent.opacity(0.8))
            Text(event.message)
                .font(Theme.mono(10))
                .foregroundStyle(color(for: event.kind))
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func color(for kind: ActivityEvent.Kind) -> Color {
        switch kind {
        case .info: return Theme.textSecondary
        case .success: return Theme.green
        case .warning: return Theme.amber
        case .error: return Theme.red
        }
    }

    // MARK: History

    @ViewBuilder
    private var historyList: some View {
        if state.history.isEmpty {
            VStack(spacing: 6) {
                Text("Porter로 kill/재시작한 프로세스가 여기 기록됩니다 — 클릭 한 번으로 다시 실행할 수 있어요.")
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.textFaint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.history) { record in
                        FeedHistoryRow(record: record)
                            .environmentObject(state)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }
}

private struct FeedHistoryRow: View {
    @EnvironmentObject var state: AppState
    let record: HistoryEntry
    @State private var hovering = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol.0)
                .font(.system(size: 10))
                .foregroundStyle(symbol.1)
                .frame(width: 14)
            Text(Self.timeFormatter.string(from: record.date))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textFaint)
            Text(record.projectName ?? record.command)
                .font(Theme.ui(11.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(":\(String(record.port))")
                .font(Theme.mono(10.5, weight: .medium))
                .foregroundStyle(Theme.green)
            if let framework = record.framework {
                Chip(text: framework, color: Theme.purple)
            }
            Text("[\(record.targetName)]")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.accent.opacity(0.8))
            Text(record.cwd)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textFaint)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()

            if hovering {
                Button {
                    state.relaunchCandidate = record
                } label: {
                    Label("재실행", systemImage: "play.fill")
                        .font(Theme.ui(10, weight: .semibold))
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
                .help("이력에서 삭제")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(hovering ? Theme.surfaceHover : .clear)
        .onHover { hovering = $0 }
        .help(record.fullCommand)
    }

    private var symbol: (String, Color) {
        switch record.action {
        case .kill: return ("stop.fill", Theme.red)
        case .restart: return ("arrow.clockwise", Theme.accent)
        case .relaunch: return ("play.fill", Theme.green)
        }
    }
}
