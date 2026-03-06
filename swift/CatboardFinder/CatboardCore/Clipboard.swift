import AppKit
import os.log

public struct Clipboard {
    /// Copy text to the system clipboard synchronously from any thread
    public static func copy(_ text: String) -> Bool {
        if text.utf8.count > FileReader.maxOutputSize {
            os_log("Output too large for clipboard: %d bytes", log: .clipboard, type: .error, text.utf8.count)
            return false
        }

        if Thread.isMainThread {
            return pasteboardWrite(text)
        } else {
            return DispatchQueue.main.sync {
                pasteboardWrite(text)
            }
        }
    }

    private static func pasteboardWrite(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        os_log("Copied %d characters to clipboard (success: %{public}@)", log: .clipboard, type: .info, text.count, String(success))
        return success
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
