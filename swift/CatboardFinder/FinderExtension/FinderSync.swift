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

        // Only add menu item for contextual menus on items, not toolbar or other contexts
        guard menuKind == .contextualMenuForItems else {
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
                message: "Please select only one file",
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

        // Process on background thread to avoid blocking Finder
        // Note: files.user-selected.read-only entitlement grants implicit access
        // to files selected in Finder without needing security-scoped resource access
        DispatchQueue.global(qos: .userInitiated).async {
            self.processFile(url)
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

            // Copy asynchronously and show notification on completion
            Clipboard.copy(text) { [weak self] success in
                if success {
                    self?.showNotification(
                        message: "Copied contents to clipboard",
                        success: true
                    )
                } else {
                    self?.showNotification(
                        message: "Failed to copy to clipboard",
                        success: false
                    )
                }
            }
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

    private func showNotification(message: String, success: Bool) {
        // Check if we have permission (cached from init)
        guard notificationPermissionGranted else {
            os_log("Cannot show notification: permission not granted", log: .ui, type: .info)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Catboard"
        content.body = message

        // macOS 13+ supports defaultCritical
        content.sound = success ? .default : .defaultCritical

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                os_log("Failed to show notification: %{public}@", log: .ui, type: .error, error.localizedDescription)
            }
        }
    }
}
