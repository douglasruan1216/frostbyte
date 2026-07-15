import SwiftUI
import AppKit

@main
struct FrostByteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var cool = CoolController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(cool)
        } label: {
            // Live heat meter: 🌙 idle · ❄️ cooling · 🟢/🟡/🔥 by temperature.
            Text(cool.menuBarEmoji)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Runs as a menu-bar accessory (no Dock icon, no window on launch).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        CoolController.shared.start()
    }

    /// Never leave a managed app paused when we quit; save the savings tally.
    func applicationWillTerminate(_ notification: Notification) {
        CoolController.shared.hardResumeAll()
        CoolController.shared.flush()
    }
}
