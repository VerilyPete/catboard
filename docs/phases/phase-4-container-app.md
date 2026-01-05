# Phase 4: Container App

**Goal:** Implement the minimal container app that guides users to enable the extension.

**Dependencies:** Phase 1 (Xcode project), Phase 2 (CatboardCore framework)

**Reference:** [finder-extension-plan.md](../finder-extension-plan.md)

---

## Table of Contents

| File | Purpose | Lines |
|------|---------|-------|
| `CatboardFinder/AppDelegate.swift` | App entry point, notification permission, enable extension dialog | ~70 |

---

## File: AppDelegate.swift

**Purpose:** Container app that requests notification permission and guides users to enable the Finder extension.

**Key behaviors:**
- Requests notification permission on launch
- Shows dialog explaining how to enable extension
- Opens System Settings/Preferences to Extensions pane
- Handles both pre-Ventura and post-Ventura URL schemes
- Safe URL handling (no force unwraps)
- Quits after last window closed

```swift
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
        // Use optional binding to avoid force unwrap crash if Apple changes URL schemes
        let urlString: String
        if #available(macOS 13.0, *) {
            // macOS Ventura and later use System Settings
            urlString = "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        } else {
            // Earlier versions use System Preferences
            urlString = "x-apple.systempreferences:com.apple.preference.extensions"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            os_log("Failed to create System Settings URL: %{public}@", log: .ui, type: .error, urlString)
            // Fallback: open Settings app directly (path differs by macOS version)
            let settingsPath: String
            if #available(macOS 13.0, *) {
                settingsPath = "/System/Applications/System Settings.app"
            } else {
                settingsPath = "/System/Applications/System Preferences.app"
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: settingsPath))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
```

---

## Notes

- The OSLog extension is defined locally since the container app doesn't need the full CatboardCore framework
- The app doesn't use a storyboard - the alert dialog is the only UI
- No window is needed; the alert dialog is sufficient

---

## Success Criteria

1. App launches without errors
2. Alert dialog appears on launch
3. "Open System Settings" button opens correct settings pane:
   - macOS 13+: System Settings → Extensions
   - macOS 11-12: System Preferences → Extensions
4. "Done" button closes the app
5. App quits after dialog is dismissed

---

## User Flow

```
┌─────────────────────────────────────┐
│  User launches CatboardFinder.app   │
└─────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────┐
│  Request notification permission    │
│  (runs in background)               │
└─────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────┐
│  Show "Enable Extension" dialog     │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ Catboard Finder Extension     │  │
│  │                               │  │
│  │ To use Catboard in Finder:    │  │
│  │ 1. Open System Settings...    │  │
│  │ 2. Enable "CatboardFinder"    │  │
│  │                               │  │
│  │ [Open System Settings] [Done] │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
                │
        ┌───────┴───────┐
        ▼               ▼
┌───────────────┐ ┌───────────────┐
│ Open Settings │ │   App Quits   │
│ (if clicked)  │ │               │
└───────────────┘ └───────────────┘
```

---

## Testing Checklist

| Scenario | Expected Result |
|----------|-----------------|
| Launch app | Alert dialog appears |
| Click "Open System Settings" on macOS 14 | System Settings opens to Extensions |
| Click "Open System Settings" on macOS 12 | System Preferences opens to Extensions |
| Click "Done" | App quits |
| Close dialog via X button | App quits |

---

## Do NOT

- Create a complex UI (minimal container app)
- Auto-enable the extension (requires user action)
- Keep the app running after dialog closes
- Modify CatboardCore files (Phase 2)
- Modify FinderSync.swift (Phase 3)
