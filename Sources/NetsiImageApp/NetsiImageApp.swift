import AppKit
import NetsiImageUI
import SwiftUI

@main
struct NetsiImageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(AppTitle.title) {
            AppShell()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { @MainActor in Self.applyWindowTitle() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in Self.applyWindowTitle() }
    }

    @MainActor
    private static func applyWindowTitle() {
        for window in NSApp.windows {
            window.title = AppTitle.title
        }
    }
}
