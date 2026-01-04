# Catboard Finder Extension Plan

A native macOS Finder Sync Extension to replace the Automator workflow, providing cleaner integration for copying file contents to clipboard.

## Motivation

The current Automator workflow approach has limitations:
- Requires manual installation to `~/Library/Services/`
- Appears under Quick Actions submenu (extra click)
- Shell script with path detection logic
- No custom icon in context menu

A Finder Sync Extension provides:
- Native contextual menu item (top-level, not buried)
- Custom icon in the menu
- Bundled with pkg installer (no separate install step)
- Better error handling and user feedback

## Architecture

### Project Structure

```
swift/CatboardFinder/
├── CatboardFinder.xcodeproj
├── CatboardFinder/                    # Container app (required but minimal)
│   ├── AppDelegate.swift              # Enables extension on first launch
│   ├── MainMenu.xib
│   ├── Assets.xcassets/               # App icon
│   └── Info.plist
│
├── FinderExtension/                   # Finder Sync Extension target
│   ├── FinderSync.swift               # FIFinderSync subclass
│   ├── FinderSync.entitlements
│   └── Info.plist
│
└── CatboardCore/                      # Shared framework target
    ├── CatboardCore.h
    ├── FileReader.swift               # Text/binary detection, routing
    ├── PDFExtractor.swift             # PDFKit text extraction + OCR fallback
    ├── OCREngine.swift                # Vision framework OCR
    ├── Clipboard.swift                # NSPasteboard wrapper
    ├── CatboardError.swift            # Error types
    └── Logging.swift                  # os_log wrapper
```

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    CatboardFinder.app                        │
│  (Container app - required for extension, minimal UI)       │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ contains
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    FinderExtension                           │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ FinderSync : FIFinderSync                           │    │
│  │   - menu(for:) → context menu with "Copy to Clipboard"   │
│  │   - copyToClipboard(_:) → handles selection        │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ uses
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     CatboardCore.framework                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ FileReader   │  │ PDFExtractor │  │  OCREngine   │      │
│  │              │  │              │  │              │      │
│  │ Routes by    │  │ PDFKit text  │  │ Vision OCR   │      │
│  │ UTType       │  │ extraction   │  │ for images   │      │
│  │              │  │ + OCR fallback│ │ and PDFs     │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Clipboard   │  │CatboardError │  │   Logging    │      │
│  │              │  │              │  │              │      │
│  │ NSPasteboard │  │ Localized    │  │  os_log      │      │
│  │ (main thread)│  │ error types  │  │  wrapper     │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Details

### Logging.swift

```swift
import os.log

extension OSLog {
    private static let subsystem = "com.verilypete.catboard.finder"

    static let fileReader = OSLog(subsystem: subsystem, category: "FileReader")
    static let pdf = OSLog(subsystem: subsystem, category: "PDF")
    static let ocr = OSLog(subsystem: subsystem, category: "OCR")
    static let clipboard = OSLog(subsystem: subsystem, category: "Clipboard")
    static let ui = OSLog(subsystem: subsystem, category: "UI")
}
```

### CatboardError.swift

```swift
import Foundation

public enum CatboardError: LocalizedError {
    case fileNotFound(URL)
    case permissionDenied(URL)
    case binaryFile(URL)
    case fileTooLarge(URL, Int64)
    case outputTooLarge(Int)
    case isDirectory(URL)
    case notFileURL(URL)
    case extractionFailed(URL, String)
    case ocrTimeout(URL)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .permissionDenied(let url):
            return "Permission denied: \(url.lastPathComponent)"
        case .binaryFile(let url):
            return "Binary file: \(url.lastPathComponent)"
        case .fileTooLarge(let url, let size):
            let sizeMB = size / 1024 / 1024
            return "File too large (\(sizeMB)MB): \(url.lastPathComponent)"
        case .outputTooLarge(let size):
            let sizeMB = size / 1024 / 1024
            return "Output too large (\(sizeMB)MB) for clipboard"
        case .isDirectory(let url):
            return "Cannot copy directory: \(url.lastPathComponent)"
        case .notFileURL(let url):
            return "Not a local file: \(url.absoluteString)"
        case .extractionFailed(_, let message):
            return message
        case .ocrTimeout(let url):
            return "OCR timed out: \(url.lastPathComponent)"
        }
    }
}
```

### FileReader.swift

```swift
import Foundation
import UniformTypeIdentifiers
import os.log

public struct FileReader {
    /// Maximum bytes to check for binary content (null bytes)
    private static let binaryCheckSize = 8192

    /// Maximum input file size (50MB)
    private static let maxFileSize: Int64 = 50 * 1024 * 1024

    /// Maximum output size for clipboard (100MB)
    public static let maxOutputSize = 100 * 1024 * 1024

    /// Read file contents, routing to appropriate handler based on type
    public static func readContents(of url: URL) throws -> String {
        // Validate this is a file URL (not a network URL)
        guard url.isFileURL else {
            throw CatboardError.notFileURL(url)
        }

        // Check file exists and is not a directory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw CatboardError.fileNotFound(url)
        }

        if isDirectory.boolValue {
            throw CatboardError.isDirectory(url)
        }

        // Check for broken symlinks
        if let _ = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
            // It's a symlink - verify the target exists
            let resolvedURL = url.resolvingSymlinksInPath()
            if !FileManager.default.fileExists(atPath: resolvedURL.path) {
                throw CatboardError.fileNotFound(url)
            }
        }

        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw CatboardError.permissionDenied(url)
        }

        // Check file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let fileSize = attributes[.size] as? Int64, fileSize > maxFileSize {
            throw CatboardError.fileTooLarge(url, fileSize)
        }

        os_log("Processing file: %{public}@", log: .fileReader, type: .info, url.path)

        // Use UTType for file type detection (more reliable than extension)
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if type.conforms(to: .pdf) {
                return try PDFExtractor.extractText(from: url)
            } else if type.conforms(to: .image) {
                return try OCREngine.extractText(from: url)
            } else if type.conforms(to: .text) || type.conforms(to: .sourceCode) {
                return try readTextFile(url)
            }
        }

        // Fallback to extension-based detection
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return try PDFExtractor.extractText(from: url)
        } else if ["png", "jpg", "jpeg", "tiff", "tif", "heic", "webp", "bmp", "gif"].contains(ext) {
            return try OCREngine.extractText(from: url)
        }

        // Default: try as text file
        return try readTextFile(url)
    }

    /// Read plain text file with binary detection and encoding detection
    private static func readTextFile(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)

        // Empty file
        if data.isEmpty {
            return ""
        }

        // Check for UTF-16/UTF-32 BOM first (these contain null bytes legitimately)
        if data.count >= 2 {
            let bom = Array(data.prefix(4))

            // UTF-32 LE BOM: FF FE 00 00 (check before UTF-16 LE since it starts the same)
            if data.count >= 4 && bom[0] == 0xFF && bom[1] == 0xFE && bom[2] == 0x00 && bom[3] == 0x00 {
                if let text = String(data: data, encoding: .utf32LittleEndian) {
                    return text
                }
            }
            // UTF-32 BE BOM: 00 00 FE FF
            if data.count >= 4 && bom[0] == 0x00 && bom[1] == 0x00 && bom[2] == 0xFE && bom[3] == 0xFF {
                if let text = String(data: data, encoding: .utf32BigEndian) {
                    return text
                }
            }
            // UTF-16 LE BOM: FF FE
            if bom[0] == 0xFF && bom[1] == 0xFE {
                if let text = String(data: data, encoding: .utf16LittleEndian) {
                    return text
                }
            }
            // UTF-16 BE BOM: FE FF
            if bom[0] == 0xFE && bom[1] == 0xFF {
                if let text = String(data: data, encoding: .utf16BigEndian) {
                    return text
                }
            }
        }

        // Check first 8KB for null bytes (indicates binary file)
        let checkRange = 0..<min(binaryCheckSize, data.count)
        if data[checkRange].contains(0) {
            // Try UTF-16 without BOM (try both byte orders)
            if let text = String(data: data, encoding: .utf16LittleEndian) {
                return text
            }
            if let text = String(data: data, encoding: .utf16BigEndian) {
                return text
            }
            throw CatboardError.binaryFile(url)
        }

        // Try common encodings in order of likelihood
        let encodings: [String.Encoding] = [.utf8, .isoLatin1, .macOSRoman, .windowsCP1252]
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                os_log("Decoded with encoding: %{public}@", log: .fileReader, type: .debug, String(describing: encoding))
                return text
            }
        }

        throw CatboardError.binaryFile(url)
    }
}
```

### PDFExtractor.swift

```swift
import Quartz
import os.log

public struct PDFExtractor {
    /// Extract text from PDF, falling back to OCR for scanned documents
    public static func extractText(from url: URL) throws -> String {
        guard let pdf = PDFDocument(url: url) else {
            throw CatboardError.extractionFailed(url, "Could not open PDF")
        }

        if pdf.isLocked {
            throw CatboardError.extractionFailed(url, "PDF is password-protected")
        }

        if pdf.pageCount == 0 {
            throw CatboardError.extractionFailed(url, "PDF has no pages")
        }

        os_log("PDF has %d pages", log: .pdf, type: .info, pdf.pageCount)

        // Try embedded text extraction first
        var allText = ""
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let text = page.string {
                if !allText.isEmpty { allText += "\n" }
                allText += text
            }
        }

        // If we got meaningful text, return it
        if !allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            os_log("Extracted embedded text from PDF", log: .pdf, type: .info)
            return allText
        }

        // Fall back to OCR for scanned PDFs
        os_log("No embedded text, falling back to OCR", log: .pdf, type: .info)
        return try OCREngine.extractText(from: url)
    }
}
```

### OCREngine.swift

```swift
import Vision
import Quartz
import AppKit
import os.log

public struct OCREngine {
    /// DPI for rendering PDF pages before OCR
    private static let renderDPI: CGFloat = 150.0

    /// Maximum pages to process (memory safety)
    private static let maxPages = 100

    /// Timeout for OCR operations (seconds)
    private static let ocrTimeout: TimeInterval = 60.0

    /// Unique page separator (unlikely to appear in real content)
    private static let pageSeparator = "══════════ Page %d ══════════"

    /// Extract text from image or PDF using Vision OCR
    public static func extractText(from url: URL) throws -> String {
        if url.pathExtension.lowercased() == "pdf" {
            return try extractFromPDF(url)
        } else {
            return try extractFromImage(url)
        }
    }

    // MARK: - Image OCR

    private static func extractFromImage(_ url: URL) throws -> String {
        guard let image = NSImage(contentsOf: url) else {
            throw CatboardError.extractionFailed(url, "Could not load image")
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CatboardError.extractionFailed(url, "Could not convert image")
        }

        let lines = try recognizeTextWithTimeout(in: cgImage, url: url)
        let result = lines.joined(separator: "\n")

        if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CatboardError.extractionFailed(url, "No text recognized in image")
        }

        return result
    }

    // MARK: - PDF OCR

    private static func extractFromPDF(_ url: URL) throws -> String {
        guard let pdf = PDFDocument(url: url) else {
            throw CatboardError.extractionFailed(url, "Could not open PDF")
        }

        if pdf.isLocked {
            throw CatboardError.extractionFailed(url, "PDF is password-protected")
        }

        let pageCount = min(pdf.pageCount, maxPages)
        if pdf.pageCount > maxPages {
            os_log("PDF has %d pages, limiting to %d", log: .ocr, type: .info, pdf.pageCount, maxPages)
        }

        var allText: [String] = []
        var failedPages: [Int] = []

        for i in 0..<pageCount {
            // Use autoreleasepool to manage memory for large PDFs
            autoreleasepool {
                guard let page = pdf.page(at: i) else {
                    os_log("Could not access page %d", log: .ocr, type: .error, i + 1)
                    failedPages.append(i + 1)
                    return
                }

                guard let cgImage = renderPage(page) else {
                    os_log("Could not render page %d (CGContext creation failed)", log: .ocr, type: .error, i + 1)
                    failedPages.append(i + 1)
                    return
                }

                do {
                    let pageText = try recognizeTextWithTimeout(in: cgImage, url: url)

                    // Add page separator for multi-page documents
                    if i > 0 && !allText.isEmpty {
                        allText.append("")
                        allText.append(String(format: pageSeparator, i + 1))
                        allText.append("")
                    }

                    allText.append(contentsOf: pageText)
                } catch let error as CatboardError {
                    if case .ocrTimeout = error {
                        os_log("OCR timed out for page %d", log: .ocr, type: .error, i + 1)
                    } else {
                        os_log("OCR failed for page %d: %{public}@", log: .ocr, type: .error, i + 1, error.localizedDescription)
                    }
                    failedPages.append(i + 1)
                } catch {
                    os_log("OCR failed for page %d: %{public}@", log: .ocr, type: .error, i + 1, error.localizedDescription)
                    failedPages.append(i + 1)
                }
            }
        }

        var result = allText.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if result.isEmpty {
            throw CatboardError.extractionFailed(url, "No text recognized in PDF")
        }

        // Append warning about failed pages if any
        if !failedPages.isEmpty {
            let pageList = failedPages.map(String.init).joined(separator: ", ")
            result += "\n\n[Warning: Failed to process pages: \(pageList)]"
            os_log("Failed to process %d pages", log: .ocr, type: .error, failedPages.count)
        }

        // Append warning about truncation if applicable
        if pdf.pageCount > maxPages {
            result += "\n\n[Warning: PDF truncated. Processed \(maxPages) of \(pdf.pageCount) pages]"
        }

        return result
    }

    // MARK: - Vision Framework with Timeout

    private static func recognizeTextWithTimeout(in image: CGImage, url: URL) throws -> [String] {
        var result: [String]?
        var ocrError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                result = try recognizeText(in: image)
            } catch {
                ocrError = error
            }
            semaphore.signal()
        }

        let timeoutResult = semaphore.wait(timeout: .now() + ocrTimeout)

        if timeoutResult == .timedOut {
            os_log("OCR operation timed out after %{public}.0f seconds", log: .ocr, type: .error, ocrTimeout)
            throw CatboardError.ocrTimeout(url)
        }

        if let error = ocrError {
            throw error
        }

        return result ?? []
    }

    private static func recognizeText(in image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        return request.results?.compactMap { observation in
            observation.topCandidates(1).first?.string
        } ?? []
    }

    // MARK: - PDF Rendering

    private static func renderPage(_ page: PDFPage) -> CGImage? {
        let rect = page.bounds(for: .mediaBox)
        let scale = renderDPI / 72.0
        let width = Int(rect.width * scale)
        let height = Int(rect.height * scale)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            os_log("Failed to create CGContext for page rendering (width: %d, height: %d)", log: .ocr, type: .error, width, height)
            return nil
        }

        // White background for scanned documents
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }
}
```

### Clipboard.swift

```swift
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
```

### FinderSync.swift

```swift
import Cocoa
import FinderSync
import UserNotifications
import os.log

class FinderSync: FIFinderSync {

    /// Cached notification permission status
    private var notificationPermissionGranted = false

    override init() {
        super.init()

        // Monitor all mounted volumes
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]

        // Request notification permission and cache result
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
        if #available(macOS 11.0, *) {
            if let symbol = NSImage(systemSymbolName: "doc.on.clipboard",
                                   accessibilityDescription: "Copy to Clipboard") {
                return symbol
            }
        }
        // Safe fallbacks - no force unwrap
        return NSImage(named: NSImage.multipleDocumentsName)
            ?? NSImage(named: NSImage.actionTemplateName)
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

        if #available(macOS 11.0, *) {
            item.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                accessibilityDescription: nil)
        }

        return menu
    }

    // MARK: - Action

    @objc func copyToClipboard(_ sender: AnyObject?) {
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

        if success {
            content.sound = .default
        } else {
            // Use default critical sound as fallback (Basso might not exist)
            if #available(macOS 12.0, *) {
                content.sound = .defaultCritical
            } else {
                // Try Basso, fall back to default
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "Basso.aiff"))
            }
        }

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
```

### Container App (AppDelegate.swift)

```swift
import Cocoa
import FinderSync
import UserNotifications

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
            os_log("Failed to create System Settings URL: %{public}@", type: .error, urlString)
            // Fallback: open System Preferences app directly
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Preferences.app"))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
```

## Code Signing & Entitlements

### FinderSync.entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
</dict>
</plist>
```

### CatboardFinder.entitlements (Container App)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
</dict>
</plist>
```

### Build Settings Requirements

- **Hardened Runtime**: Enabled
- **Code Signing Identity**: Developer ID Application (for distribution)
- **Development Team**: Must be set
- **Deployment Target**: macOS 11.0 (for SF Symbols and UserNotifications)

## Distribution

### Notarization Process

```bash
# 1. Archive the app
xcodebuild -project CatboardFinder.xcodeproj \
    -scheme CatboardFinder \
    -configuration Release \
    -archivePath build/CatboardFinder.xcarchive \
    archive

# 2. Export the app
xcodebuild -exportArchive \
    -archivePath build/CatboardFinder.xcarchive \
    -exportPath build \
    -exportOptionsPlist ExportOptions.plist

# 3. Create zip for notarization
ditto -c -k --keepParent build/CatboardFinder.app CatboardFinder.zip

# 4. Submit for notarization
xcrun notarytool submit CatboardFinder.zip \
    --apple-id "your@email.com" \
    --team-id "TEAMID" \
    --password "app-specific-password" \
    --wait

# 5. Staple the notarization ticket
xcrun stapler staple build/CatboardFinder.app

# 6. Verify
spctl --assess --verbose build/CatboardFinder.app
```

### ExportOptions.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <!-- Replace YOUR_TEAM_ID with your actual Apple Developer Team ID -->
    <!-- Find it at: https://developer.apple.com/account -> Membership Details -->
    <string>YOUR_TEAM_ID</string>
</dict>
</plist>
```

### pkg Installer Integration

The Finder extension app will be bundled in the existing pkg installer:

```
CatboardInstaller.pkg
├── catboard (CLI binary) → /usr/local/bin/
├── catboard-ocr (Swift OCR helper) → /usr/local/bin/
└── CatboardFinder.app → /Applications/
```

**Important**: Do NOT auto-launch the app from the installer post-install script. The installer runs as root, which would cause security issues. Instead, include instructions in the installer's conclusion page:

```html
<!-- conclusion.html -->
<html>
<body>
<h1>Installation Complete</h1>
<p>To enable the Finder extension:</p>
<ol>
    <li>Open <strong>CatboardFinder</strong> from Applications</li>
    <li>Click "Open System Settings" when prompted</li>
    <li>Enable the <strong>CatboardFinder</strong> extension</li>
</ol>
<p>Then right-click any file in Finder to see "Copy to Clipboard"</p>
</body>
</html>
```

### Homebrew Cask

For Homebrew distribution, create a cask formula:

```ruby
cask "catboard-finder" do
  version "0.2.0"
  sha256 "..."

  url "https://github.com/VerilyPete/catboard/releases/download/v#{version}/CatboardFinder.app.zip"
  name "Catboard Finder Extension"
  homepage "https://github.com/VerilyPete/catboard"

  depends_on macos: ">= :big_sur"

  app "CatboardFinder.app"

  postflight do
    # Open the app to trigger the enable-extension dialog
    system_command "/usr/bin/open", args: ["/Applications/CatboardFinder.app"]
  end

  uninstall quit: "com.verilypete.CatboardFinder"

  zap trash: [
    "~/Library/Caches/com.verilypete.CatboardFinder",
    "~/Library/Preferences/com.verilypete.CatboardFinder.plist",
  ]
end
```

## Migration Path

1. Keep existing Automator workflow for backwards compatibility
2. Document Finder extension as preferred method
3. Deprecate workflow in future release

## Testing Plan

### Unit Tests (CatboardCore)

- FileReader: text files, binary detection, routing, symlinks, directories
- FileReader: encoding detection (UTF-8, UTF-16 LE/BE, Latin-1)
- FileReader: file size limits, output size limits
- FileReader: file URL validation (reject network URLs)
- PDFExtractor: text PDFs, scanned PDFs, password-protected
- OCREngine: various image formats, multi-page PDFs
- OCREngine: timeout handling
- OCREngine: memory management for large PDFs
- Clipboard: copy/paste roundtrip, thread safety, size limits

### Integration Tests

- Extension loads correctly
- Context menu appears for files (not directories)
- Various file types process correctly
- Error notifications display properly
- Multiple selection handling
- Notification permission denied scenario
- OCR timeout scenario

### Manual Testing

- Fresh install on clean macOS
- Upgrade from workflow-only installation
- Various file types (text, PDF, images)
- Large files / slow OCR
- Permission denied scenarios
- Broken symlinks
- Empty files
- Files with unusual encodings
- Very large output (test clipboard size limit)
- Network URLs (should be rejected)

## Implementation Dependencies

This plan focuses on what needs to be built, not when. Key dependencies:

1. **CatboardCore framework** - must be complete before extension
2. **Signing setup** - required before any testing on real hardware
3. **Container app** - simple but required for extension to work
4. **Extension** - main deliverable, depends on framework
5. **Notarization** - required before distribution
6. **Installer integration** - final step

## Design Decisions

### Resolved

1. **Multiple file selection**: Reject with helpful message. Concatenating files has unclear UX for notifications and error handling.

2. **Threading**: File processing on background queue, clipboard access on main queue (required by AppKit) with async completion handler, notifications via UserNotifications framework.

3. **File type detection**: Use UTType (Uniform Type Identifiers) with fallback to extension-based detection for compatibility.

4. **Notifications**: Use modern UserNotifications framework (NSUserNotification deprecated in macOS 11, removed in macOS 14). Cache permission status and gracefully handle denied permissions.

5. **System Settings URL**: Handle both pre-Ventura (System Preferences) and post-Ventura (System Settings) URL schemes with safe optional binding.

6. **Size limits**: 50MB input file limit, 100MB output limit for clipboard. Prevents memory issues and clipboard hangs.

7. **OCR timeout**: 60 second timeout per OCR operation prevents indefinite hangs on complex images.

8. **Page separator**: Use distinctive unicode separator (`══════════`) to avoid conflicts with document content.

9. **Notification sounds**: Use system default sounds with fallback for compatibility across macOS versions.

### Open Questions

1. **Progress indication**: Long OCR operations have no feedback. Consider adding a progress HUD or menu bar indicator in future version.

2. **Preferences**: Should the app have preferences (OCR language, notification sounds, etc.)? Defer to future version.

3. **CLI coexistence**: Keep Rust CLI separate for now. Single Swift codebase is a larger refactor for a future consideration.
