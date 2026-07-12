import AppKit
import SwiftUI

/// Menu-bar drop-down: the selected target's listening ports with one-click
/// kill — the "glance and act" surface. Shares AppState with the main window;
/// opening the panel makes the app visible, which already triggers the
/// catch-up refresh in AppState's occlusion observer.
struct MenuBarPanel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            portList
            Divider().overlay(Theme.border)
            footer
        }
        .frame(width: 360)
        .background(Theme.background)
        .task { await state.refresh() }
    }

    // MARK: Header — target picker + count + refresh

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(state.targets) { target in
                    Button {
                        state.select(target: target)
                    } label: {
                        if target.id == state.selectedTargetID {
                            Label(target.name, systemImage: "checkmark")
                        } else {
                            Text(target.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: state.selectedTarget.isLocal ? "laptopcomputer" : "server.rack")
                        .font(.system(size: 10))
                    Text(state.selectedTarget.name)
                        .font(Theme.ui(12, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            if state.isScanning {
                ProgressView().controlSize(.small)
            } else {
                Text(L("LISTEN \(state.ports.count)개"))
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Button {
                Task { await state.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .help(L("새로고침"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: Port rows

    @ViewBuilder
    private var portList: some View {
        if state.ports.isEmpty {
            Text(state.isScanning ? L("불러오는 중…") : L("LISTEN 중인 TCP 포트가 없습니다"))
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(state.ports) { entry in
                        MenuBarPortRow(entry: entry)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 380)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button(L("Porter 열기")) { openMainWindow() }
                .buttonStyle(.plain)
                .font(Theme.ui(11.5, weight: .semibold))
                .foregroundStyle(Theme.accent)

            Spacer()

            SettingsLink {
                Text(L("설정…"))
                    .font(Theme.ui(11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            // Settings opened from a menu-bar panel lands behind other apps
            // unless the app is activated alongside.
            .simultaneousGesture(TapGesture().onEnded {
                NSApp.activate(ignoringOtherApps: true)
            })

            Button(L("Porter 종료")) { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    /// Restore the regular app (Dock icon + main window) from menu-bar-only mode.
    private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        if let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue.hasPrefix("main") == true
        }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Row

private struct MenuBarPortRow: View {
    @EnvironmentObject var state: AppState
    let entry: PortEntry
    @State private var hovering = false
    @State private var killing = false

    /// Light-weight guard: full protected detection (fullCommand paths)
    /// needs a detail fetch; user/pid catches the obvious system daemons.
    private var looksProtected: Bool {
        entry.user == "root" || (entry.pid > 0 && entry.pid < 300)
    }

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: entry.devLabel != nil ? Theme.green : Theme.textFaint, size: 5)
            Text(String(entry.port))
                .font(Theme.mono(12, weight: .semibold))
                .foregroundStyle(entry.devLabel != nil ? Theme.green : Theme.textPrimary)
                .frame(width: 46, alignment: .leading)
            Text(entry.command)
                .font(Theme.ui(11.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if let project = state.projects[entry.pid], let name = project.name {
                Text(name)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let primary = state.urls(for: entry).first {
                Button {
                    state.open(primary)
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 10.5))
                        .foregroundStyle(hovering ? Theme.accent : Theme.textFaint)
                }
                .buttonStyle(.plain)
                .help(L("브라우저에서 열기"))
            }

            if killing {
                ProgressView().controlSize(.mini)
            } else {
                Button {
                    killing = true
                    Task {
                        _ = await state.kill(entry, force: false)
                        killing = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(hovering ? Theme.red : Theme.textFaint)
                }
                .buttonStyle(.plain)
                .disabled(looksProtected || state.isActing)
                .help(looksProtected
                      ? L("시스템/보호 프로세스 — 메인 창에서 확인 후 종료하세요")
                      : L("프로세스 종료"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(hovering ? Theme.surface : .clear)
        .onHover { hovering = $0 }
    }
}
