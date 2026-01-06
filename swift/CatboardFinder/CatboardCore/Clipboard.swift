import AppKit
import os.log

public struct Clipboard {
    /// Copy text to the system clipboard asynchronously with completion handler
    public static func copy(_ text: String, completion: @escaping (Bool) -> Void) {
        // Check output size before copying
        if text.utf8.count > FileReader.maxOutputSize {
            os_log("Output too large for clipboard: %d bytes", log: .clipboard, type: .error, text.utf8.count)
            completion(false)
            return
        }

        // NSPasteboard MUST be accessed on main thread
        DispatchQueue.main.async {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let success = pasteboard.setString(text, forType: .string)
            os_log("Copied %d characters to clipboard (success: %{public}@)", log: .clipboard, type: .info, text.count, String(success))
            completion(success)
        }
    }

    /// Copy text synchronously (must be called from main thread)
    /// Returns false if output is too large
    public static func copySync(_ text: String) -> Bool {
        assert(Thread.isMainThread, "copySync must be called from main thread")

        // Check output size before copying
        if text.utf8.count > FileReader.maxOutputSize {
            os_log("Output too large for clipboard: %d bytes", log: .clipboard, type: .error, text.utf8.count)
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// Get current clipboard text (for testing)
    public static func getText() -> String? {
        if Thread.isMainThread {
            return NSPasteboard.general.string(forType: .string)
        } else {
            return DispatchQueue.main.sync {
                NSPasteboard.general.string(forType: .string)
            }
        }
    }
}
