import SwiftUI

/// Orca-style 3-panel workspace: targets / ports / inspector, with an
/// activity feed strip along the bottom.
struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView()
                Divider().overlay(Theme.border)
                PortListView()
                if let selected = state.selectedPort {
                    Divider().overlay(Theme.border)
                    DetailPanel(entry: selected)
                }
            }
            ActivityFeedView()
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .frame(minWidth: 980, minHeight: 620)
        .task {
            if let dir = LaunchMode.screenshotDir {
                await ScreenshotDirector.run(state: state, directory: dir)
                return
            }
            if state.isDemo { return } // seeded data, nothing to scan
            state.log(.info, "Porter 시작")
            await state.refresh()
        }
        .sheet(item: $state.killCandidate) { entry in
            KillConfirmSheet(entry: entry).environmentObject(state)
        }
        .sheet(item: $state.restartCandidate) { entry in
            RestartConfirmSheet(entry: entry).environmentObject(state)
        }
        .sheet(isPresented: $state.showAddTarget) {
            AddTargetSheet().environmentObject(state)
        }
        .sheet(item: $state.passwordPromptTarget) { target in
            PasswordPromptSheet(target: target).environmentObject(state)
        }
        .sheet(item: $state.relaunchCandidate) { record in
            RelaunchSheet(record: record).environmentObject(state)
        }
    }
}
