import Sparkle
import SwiftUI

/// SwiftUI app entry. Launched from main.swift (no @main — the executable
/// also has a CLI scan mode).
struct PorterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState(demo: LaunchMode.isDemo)
    // Sparkle needs a real .app bundle (SUFeedURL/SUPublicEDKey in Info.plist);
    // don't start it for bare `swift run` binaries or demo/screenshot runs,
    // where an update prompt would be noise.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: !LaunchMode.isDemo && Bundle.main.bundleIdentifier != nil,
        updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}

/// SPM executables launch as background processes; promote to a regular
/// foreground app so the window and Dock icon appear.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Dock icon for bare-binary runs (swift run); the .app bundle carries
        // its own .icns for Finder/Launchpad.
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
