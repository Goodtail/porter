import AppKit
import SwiftUI

/// `--screenshot <dir>` mode: stage the demo UI, render the window into PNGs
/// via `cacheDisplay` (in-process — needs no Screen Recording permission),
/// then quit. Used to regenerate the README screenshots deterministically.
@MainActor
enum ScreenshotDirector {
    static func run(state: AppState, directory: String) async {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        // Let SwiftUI finish its first layout pass.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else {
            fputs("screenshot: no visible window\n", stderr)
            NSApp.terminate(nil)
            return
        }
        window.setContentSize(NSSize(width: 1280, height: 800))
        window.center()
        window.makeFirstResponder(nil) // no caret in the search field
        try? await Task.sleep(nanoseconds: 500_000_000)

        capture(window, to: directory + "/screenshot-overview.png")

        // Second shot: dev port selected, detail panel with LIVE log follow.
        if let next = state.ports.first(where: { $0.port == 3000 }) {
            state.selectPort(next)
            if let log = state.detail?.logFiles.first {
                state.startLogStream(file: log)
            }
        }
        try? await Task.sleep(nanoseconds: 800_000_000)
        capture(window, to: directory + "/screenshot-detail.png")

        // Third shot: the restart sheet with its PORT field (moved to :3001).
        if let next = state.ports.first(where: { $0.port == 3000 }) {
            state.restartCandidate = next
        }
        try? await Task.sleep(nanoseconds: 900_000_000)
        if let sheet = window.attachedSheet {
            capture(sheet, to: directory + "/screenshot-restart.png")
        }

        // NSApp.terminate can stall while a sheet's modal session is active;
        // everything is on disk, so exit outright.
        exit(0)
    }

    /// Renders the window's frame view (title bar, rounded corners included)
    /// into a retina PNG.
    private static func capture(_ window: NSWindow, to path: String) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fputs("screenshot: cannot build bitmap rep\n", stderr)
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("screenshot: wrote \(path) (\(Int(rep.pixelsWide))x\(Int(rep.pixelsHigh)))")
        } catch {
            fputs("screenshot: write failed — \(error.localizedDescription)\n", stderr)
        }
    }
}
