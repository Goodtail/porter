import ServiceManagement
import Sparkle
import SwiftUI

/// Settings window (⌘,) — login item, menu bar presence, updates.
struct SettingsView: View {
    private let updater: SPUUpdater
    @ObservedObject private var updatesViewModel: CheckForUpdatesViewModel

    @AppStorage("menuBarEnabled") private var menuBarEnabled = true
    @State private var launchAtLogin: Bool
    @State private var loginItemError: String?
    @State private var autoCheckUpdates: Bool

    /// Login items need a real .app bundle; bare `swift run` binaries can't register.
    private let canManageLoginItem = Bundle.main.bundleIdentifier != nil

    init(updater: SPUUpdater) {
        self.updater = updater
        self.updatesViewModel = CheckForUpdatesViewModel(updater: updater)
        _launchAtLogin = State(initialValue:
            Bundle.main.bundleIdentifier != nil && SMAppService.mainApp.status == .enabled)
        _autoCheckUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        Form {
            Section(L("일반")) {
                Toggle(L("로그인 시 Porter 자동 실행"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLoginItem(enabled) }
                    .disabled(!canManageLoginItem)
                if !canManageLoginItem {
                    Text(L("로그인 자동 실행은 Porter.app 번들로 실행할 때만 설정할 수 있습니다."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Toggle(L("메뉴 막대 아이콘 표시"), isOn: $menuBarEnabled)
                Text(L("메뉴 막대가 켜져 있으면 창을 닫아도 Porter가 백그라운드에서 계속 실행됩니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("업데이트")) {
                Toggle(L("자동으로 업데이트 확인"), isOn: $autoCheckUpdates)
                    .onChange(of: autoCheckUpdates) { _, enabled in
                        updater.automaticallyChecksForUpdates = enabled
                    }
                Button(L("지금 업데이트 확인")) { updater.checkForUpdates() }
                    .disabled(!updatesViewModel.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLoginItem(_ enabled: Bool) {
        loginItemError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let message = error.localizedDescription
            loginItemError = L("로그인 항목 등록 실패: \(message)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
