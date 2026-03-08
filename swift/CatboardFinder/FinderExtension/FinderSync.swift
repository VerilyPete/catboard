import Cocoa
import FinderSync
import UserNotifications
import os.log
import CatboardCore

class FinderSync: FIFinderSync {

    /// Thread-safe cached notification permission status
    private let permissionQueue = DispatchQueue(label: "com.verilypete.catboard.permission")
    private var _notificationPermissionGranted = false
    private var notificationPermissionGranted: Bool {
        get { permissionQueue.sync { _notificationPermissionGranted } }
        set { permissionQueue.sync { _notificationPermissionGranted = newValue } }
    }

    override init() {
        super.init()

        // Monitor all mounted volumes
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]

        // Request notification permission and cache result (thread-safe)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            self?.notificationPermissionGranted = granted
            if let error = error {
                os_log("Notification permission error: %{public}@", log: .ui, type: .error, error.localizedDescription)
            } else {
                os_log("Notification permission granted: %{public}@", log: .ui, type: .info, String(granted))
            }
        }

        os_log("Catboard Finder Extension initialized", log: .ui, type: .info)
    }

    // MARK: - Toolbar Item (optional - appears in Finder toolbar)

    override var toolbarItemName: String {
        return "Catboard"
    }

    override var toolbarItemToolTip: String {
        return "Copy file contents to clipboard"
    }

    override var toolbarItemImage: NSImage {
        // SF Symbols available on macOS 13+
        return NSImage(systemSymbolName: "doc.on.clipboard",
                      accessibilityDescription: "Copy to Clipboard")
            ?? NSImage(named: NSImage.multipleDocumentsName)
            ?? NSImage()
    }

    // MARK: - Context Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")

        // Add menu item for contextual menus on items and toolbar button
        guard menuKind == .contextualMenuForItems || menuKind == .toolbarItemMenu else {
            return menu
        }

        let item = menu.addItem(
            withTitle: "Copy to Clipboard",
            action: #selector(copyToClipboard(_:)),
            keyEquivalent: ""
        )
        item.target = self

        item.image = NSImage(systemSymbolName: "doc.on.clipboard",
                            accessibilityDescription: nil)

        return menu
    }

    // MARK: - Action

    @objc func copyToClipboard(_ sender: AnyObject?) {
        os_log("copyToClipboard action triggered", log: .ui, type: .info)

        guard let items = FIFinderSyncController.default().selectedItemURLs(),
              !items.isEmpty else {
            showNotification(
                message: "No file selected",
                success: false
            )
            return
        }

        // Handle multiple selection
        if items.count > 1 {
            showNotification(
                message: "Please select only one item",
                success: false
            )
            return
        }

        let url = items[0]

        // Validate this is a file URL
        guard url.isFileURL else {
            showNotification(
                message: "Not a local file",
                success: false
            )
            return
        }

        os_log("User selected: %{public}@", log: .ui, type: .info, url.path)

        // Check if selected item is a directory
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        // Process on background thread to avoid blocking Finder
        DispatchQueue.global(qos: .userInitiated).async {
            if isDirectory.boolValue {
                self.processDirectory(url)
            } else {
                self.processFile(url)
            }
        }
    }

    private func processDirectory(_ url: URL) {
        do {
            let result = try TreeGenerator.generate(directories: [url])
            if result.output.isEmpty {
                showNotification(message: "Directory is empty", success: false)
                return
            }
            let success = Clipboard.copy(result.output)
            var message = "Copied \(result.filesIncluded) files to clipboard"
            if result.truncated { message += " (truncated)" }
            showNotification(message: message, success: success)
        } catch {
            os_log("Error processing directory: %{public}@", log: .ui, type: .error, error.localizedDescription)
            var message = error.localizedDescription
            if message.count > 100 { message = String(message.prefix(97)) + "..." }
            showNotification(message: message, success: false)
        }
    }

    private func processFile(_ url: URL) {
        do {
            let text = try FileReader.readContents(of: url)

            // Check for empty content
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showNotification(
                    message: "File is empty",
                    success: false
                )
                return
            }

            // Check output size
            if text.utf8.count > FileReader.maxOutputSize {
                let sizeMB = text.utf8.count / 1024 / 1024
                showNotification(
                    message: "Output too large (\(sizeMB)MB) for clipboard",
                    success: false
                )
                return
            }

            let success = Clipboard.copy(text)
            showNotification(
                message: success ? "Copied contents to clipboard" : "Failed to copy to clipboard",
                success: success
            )
        } catch {
            os_log("Error processing file: %{public}@", log: .ui, type: .error, error.localizedDescription)

            // Truncate long error messages for notification
            var message = error.localizedDescription
            if message.count > 100 {
                message = String(message.prefix(97)) + "..."
            }

            showNotification(
                message: message,
                success: false
            )
        }
    }

    // MARK: - Notifications (using modern UserNotifications framework)

    private static let successSound = NSSound(named: NSSound.Name("Glass"))
    private static let failureSound = NSSound(named: NSSound.Name("Basso"))

    private func playSoundFeedback(success: Bool) {
        DispatchQueue.main.async {
            let sound = success ? Self.successSound : Self.failureSound
            guard let sound = sound else {
                os_log("Feedback sound not found", log: .ui, type: .error)
                return
            }
            sound.play()
        }
    }

    private func showNotification(message: String, success: Bool) {
        playSoundFeedback(success: success)

        guard notificationPermissionGranted else {
            os_log("Notification not shown (permission denied): %{public}@", log: .ui, type: .info, message)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Catboard"
        content.body = message
        content.sound = nil  // Sound already played via NSSound

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                os_log("Failed to show notification: %{public}@", log: .ui, type: .error, error.localizedDescription)
            }
        }
    }
}
