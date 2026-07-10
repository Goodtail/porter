import SwiftUI

/// SwiftUI app entry. Launched from main.swift (no @main — the executable
/// also has a CLI scan mode).
struct PorterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// SPM executables launch as background processes; promote to a regular
/// foreground app so the window and Dock icon appear.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
