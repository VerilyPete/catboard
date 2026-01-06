import Cocoa
import UserNotifications
import os.log

// Local OSLog extension (container app doesn't need full CatboardCore)
extension OSLog {
    fileprivate static let ui = OSLog(subsystem: "com.verilypete.catboard.finder", category: "UI")
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permission for the extension
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Guide user to enable the extension
        showEnableExtensionDialog()
    }

    private func showEnableExtensionDialog() {
        let alert = NSAlert()
        alert.messageText = "Catboard Finder Extension"
        alert.informativeText = """
            To use Catboard in Finder:

            1. Open System Settings → Privacy & Security → Extensions → Finder
            2. Enable "CatboardFinder"

            Then right-click any file to see "Copy to Clipboard"
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Done")

        if alert.runModal() == .alertFirstButtonReturn {
            openExtensionsSettings()
        }
    }

    private func openExtensionsSettings() {
        // macOS 13+ uses System Settings
        let urlString = "x-apple.systempreferences:com.apple.ExtensionsPreferences"

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            os_log("Failed to create System Settings URL: %{public}@", log: .ui, type: .error, urlString)
            // Fallback: open System Settings app directly
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
