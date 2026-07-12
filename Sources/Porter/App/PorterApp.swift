import Sparkle
import SwiftUI

/// SwiftUI app entry. Launched from main.swift (no @main — the executable
/// also has a CLI scan mode).
struct PorterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState(demo: LaunchMode.isDemo)
    // Menu-bar presence doubles as "keep running without windows" — see
    // AppDelegate.applicationShouldTerminateAfterLastWindowClosed.
    @AppStorage("menuBarEnabled") private var menuBarEnabled = true
    // Sparkle needs a real .app bundle (SUFeedURL/SUPublicEDKey in Info.plist);
    // don't start it for bare `swift run` binaries or demo/screenshot runs,
    // where an update prompt would be noise.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: !LaunchMode.isDemo && Bundle.main.bundleIdentifier != nil,
        updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        WindowGroup(id: "main") {
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

        Settings {
            SettingsView(updater: updaterController.updater)
        }

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarPanel()
                .environmentObject(state)
        } label: {
            if let icon = Self.statusBarIcon {
                Image(nsImage: icon)
            } else {
                Image(systemName: "circle.grid.2x2.fill")
            }
        }
        .menuBarExtraStyle(.window)
    }

    /// The app logo sized for the status bar (18pt; full-res bitmap kept so
    /// retina draws stay crisp). Colored on purpose — it's the brand mark.
    private static let statusBarIcon: NSImage? = {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
              let icon = NSImage(contentsOf: url) else { return nil }
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }()
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

    /// With the menu bar icon on, closing the last window drops Porter into
    /// menu-bar-only mode (no Dock icon) instead of quitting; MenuBarPanel's
    /// "Porter 열기" restores the regular app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let menuBarEnabled = UserDefaults.standard.object(forKey: "menuBarEnabled") as? Bool ?? true
        if menuBarEnabled {
            NSApp.setActivationPolicy(.accessory)
            return false
        }
        return true
    }

    /// Relaunch from Finder/Spotlight while in menu-bar-only mode: bring the
    /// regular app back so SwiftUI restores the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
}
