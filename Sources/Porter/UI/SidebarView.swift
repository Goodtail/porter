import SwiftUI

/// Left rail: local + SSH targets with connection state (F1).
struct SidebarView: View {
    @EnvironmentObject var state: AppState

    private var sshConfigTargets: [Target] {
        state.targets.filter { $0.fromSSHConfig }
    }
    private var customTargets: [Target] {
        state.targets.filter { $0.kind == .ssh && !$0.fromSSHConfig }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App mark — the real app icon, not a symbol stand-in
            HStack(spacing: 8) {
                if let logo = AppAssets.logo {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.green)
                }
                Text("Porter")
                    .font(Theme.ui(15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader("LOCAL")
                    targetRow(.local)

                    if !sshConfigTargets.isEmpty {
                        sectionHeader("SSH CONFIG").padding(.top, 14)
                        ForEach(sshConfigTargets) { targetRow($0) }
                    }

                    sectionHeader("REMOTE").padding(.top, 14)
                    ForEach(customTargets) { targetRow($0) }

                    Button {
                        state.showAddTarget = true
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("SSH 타깃 추가")
                                .font(Theme.ui(12))
                        }
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            // Footer: refresh status
            VStack(alignment: .leading, spacing: 5) {
                Divider().overlay(Theme.border)
                HStack(spacing: 6) {
                    StatusDot(color: state.autoRefresh ? Theme.green : Theme.textFaint, size: 6)
                    Text(state.autoRefresh
                         ? "\(state.refreshIntervalSeconds)초마다 자동 새로고침"
                         : "자동 새로고침 꺼짐")
                        .font(Theme.ui(10))
                        .foregroundStyle(Theme.textFaint)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 210)
        .background(Theme.surface)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.ui(9.5, weight: .bold))
            .foregroundStyle(Theme.textFaint)
            .kerning(0.8)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
    }

    private func targetRow(_ target: Target) -> some View {
        let isSelected = state.selectedTargetID == target.id
        let conn = state.connectionStates[target.id] ?? .unknown

        return Button {
            state.select(target: target)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: target.isLocal ? "laptopcomputer" : "server.rack")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(target.name)
                        .font(Theme.ui(12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                    Text(target.subtitle)
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                connectionDot(conn)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected ? Theme.surfaceHigh : .clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if target.kind == .ssh && !target.fromSSHConfig {
                Button("타깃 삭제", role: .destructive) { state.removeTarget(target) }
            }
        }
        .help(conn.isFailed ? failureMessage(conn) : target.subtitle)
    }

    @ViewBuilder
    private func connectionDot(_ conn: ConnectionState) -> some View {
        switch conn {
        case .unknown: EmptyView()
        case .checking: ProgressView().controlSize(.mini)
        case .connected: StatusDot(color: Theme.green, size: 6)
        case .failed: StatusDot(color: Theme.red, size: 6)
        }
    }

    private func failureMessage(_ conn: ConnectionState) -> String {
        if case .failed(let msg) = conn { return msg }
        return ""
    }
}
