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
    └── CatboardError.swift            # Error types
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
│  │ extension    │  │ extraction   │  │ for images   │      │
│  │              │  │ + OCR fallback│ │ and PDFs     │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│  ┌──────────────┐  ┌──────────────┐                        │
│  │  Clipboard   │  │CatboardError │                        │
│  │              │  │              │                        │
│  │ NSPasteboard │  │ Localized    │                        │
│  │ wrapper      │  │ error types  │                        │
│  └──────────────┘  └──────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Details

### CatboardError.swift

```swift
import Foundation

public enum CatboardError: LocalizedError {
    case fileNotFound(URL)
    case permissionDenied(URL)
    case binaryFile(URL)
    case extractionFailed(URL, String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .permissionDenied(let url):
            return "Permission denied: \(url.lastPathComponent)"
        case .binaryFile(let url):
            return "Binary file: \(url.lastPathComponent)"
        case .extractionFailed(_, let message):
            return message
        }
    }
}
```

### FileReader.swift

```swift
import Foundation

public struct FileReader {
    /// Maximum bytes to check for binary content (null bytes)
    private static let binaryCheckSize = 8192

    /// Supported image extensions for OCR
    private static let imageExtensions = Set([
        "png", "jpg", "jpeg", "tiff", "tif", "heic", "webp", "bmp", "gif"
    ])

    /// Read file contents, routing to appropriate handler based on type
    public static func readContents(of url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CatboardError.fileNotFound(url)
        }

        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw CatboardError.permissionDenied(url)
        }

        let ext = url.pathExtension.lowercased()

        if ext == "pdf" {
            return try PDFExtractor.extractText(from: url)
        } else if imageExtensions.contains(ext) {
            return try OCREngine.extractText(from: url)
        } else {
            return try readTextFile(url)
        }
    }

    /// Read plain text file with binary detection
    private static func readTextFile(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)

        // Check first 8KB for null bytes (indicates binary file)
        let checkRange = 0..<min(binaryCheckSize, data.count)
        if data[checkRange].contains(0) {
            throw CatboardError.binaryFile(url)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw CatboardError.binaryFile(url)
        }

        return text
    }
}
```

### PDFExtractor.swift

```swift
import Quartz

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
            return allText
        }

        // Fall back to OCR for scanned PDFs
        return try OCREngine.extractText(from: url)
    }
}
```

### OCREngine.swift

```swift
import Vision
import Quartz
import AppKit

public struct OCREngine {
    /// DPI for rendering PDF pages before OCR
    private static let renderDPI: CGFloat = 150.0

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

        let lines = try recognizeText(in: cgImage)
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

        var allText: [String] = []
        var pageErrors = 0

        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else {
                pageErrors += 1
                continue
            }

            guard let cgImage = renderPage(page) else {
                pageErrors += 1
                continue
            }

            do {
                let pageText = try recognizeText(in: cgImage)

                // Add page separator for multi-page documents
                if i > 0 && !allText.isEmpty {
                    allText.append("")
                    allText.append("--- Page \(i + 1) ---")
                    allText.append("")
                }

                allText.append(contentsOf: pageText)
            } catch {
                pageErrors += 1
            }
        }

        let result = allText.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if result.isEmpty {
            throw CatboardError.extractionFailed(url, "No text recognized in PDF")
        }

        return result
    }

    // MARK: - Vision Framework

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

public struct Clipboard {
    /// Copy text to the system clipboard
    public static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Get current clipboard text (for testing)
    public static func getText() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }
}
```

### FinderSync.swift

```swift
import Cocoa
import FinderSync

class FinderSync: FIFinderSync {

    override init() {
        super.init()

        // Monitor all mounted volumes
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]

        NSLog("Catboard Finder Extension initialized")
    }

    // MARK: - Toolbar Item

    override var toolbarItemName: String {
        return "Catboard"
    }

    override var toolbarItemToolTip: String {
        return "Copy file contents to clipboard"
    }

    override var toolbarItemImage: NSImage {
        // Use SF Symbol on macOS 11+, fallback for older versions
        if #available(macOS 11.0, *) {
            return NSImage(systemSymbolName: "doc.on.clipboard",
                          accessibilityDescription: "Copy to Clipboard")
                ?? NSImage(named: NSImage.multipleDocumentsName)!
        } else {
            return NSImage(named: NSImage.multipleDocumentsName)!
        }
    }

    // MARK: - Context Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")

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
              let url = items.first else {
            showNotification(
                message: "No file selected",
                success: false
            )
            return
        }

        // Process on background thread to avoid blocking Finder
        DispatchQueue.global(qos: .userInitiated).async {
            self.processFile(url)
        }
    }

    private func processFile(_ url: URL) {
        do {
            let text = try FileReader.readContents(of: url)
            Clipboard.copy(text)

            showNotification(
                message: "Copied contents to clipboard",
                success: true
            )
        } catch {
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

    // MARK: - Notifications

    private func showNotification(message: String, success: Bool) {
        DispatchQueue.main.async {
            let notification = NSUserNotification()
            notification.title = "Catboard"
            notification.informativeText = message
            notification.soundName = success ? "Glass" : "Basso"

            NSUserNotificationCenter.default.deliver(notification)
        }
    }
}
```

### Container App (AppDelegate.swift)

```swift
import Cocoa
import FinderSync

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check if extension is enabled
        checkExtensionStatus()
    }

    private func checkExtensionStatus() {
        // Open System Preferences to Extensions pane if needed
        // This guides users to enable the extension on first launch

        let alert = NSAlert()
        alert.messageText = "Catboard Finder Extension"
        alert.informativeText = """
            To use Catboard in Finder:

            1. Open System Preferences → Extensions → Finder
            2. Enable "CatboardFinder"

            Then right-click any file to see "Copy to Clipboard"
            """
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Done")

        if alert.runModal() == .alertFirstButtonReturn {
            // Open Extensions preference pane
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.extensions")!
            )
        }
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
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

### Requirements

- Apple Developer account (for signing)
- Hardened Runtime enabled
- Notarization for distribution outside App Store

## Distribution

### pkg Installer Integration

The Finder extension app will be bundled in the existing pkg installer:

```
CatboardInstaller.pkg
├── catboard (CLI binary) → /usr/local/bin/
├── catboard-ocr (Swift OCR helper) → /usr/local/bin/
└── CatboardFinder.app → /Applications/
```

Post-install script can optionally launch the app to prompt extension enablement.

### Homebrew Cask

For Homebrew distribution, create a cask formula:

```ruby
cask "catboard-finder" do
  version "0.2.0"
  sha256 "..."

  url "https://github.com/VerilyPete/catboard/releases/download/v#{version}/CatboardFinder.app.zip"
  name "Catboard Finder Extension"
  homepage "https://github.com/VerilyPete/catboard"

  app "CatboardFinder.app"

  postflight do
    system_command "/usr/bin/open", args: ["/Applications/CatboardFinder.app"]
  end
end
```

## Migration Path

1. Keep existing Automator workflow for backwards compatibility
2. Document Finder extension as preferred method
3. Deprecate workflow in future release

## Testing Plan

### Unit Tests (CatboardCore)

- FileReader: text files, binary detection, routing
- PDFExtractor: text PDFs, scanned PDFs, password-protected
- OCREngine: various image formats, multi-page PDFs
- Clipboard: copy/paste roundtrip

### Integration Tests

- Extension loads correctly
- Context menu appears for files
- Various file types process correctly
- Error notifications display properly

### Manual Testing

- Fresh install on clean macOS
- Upgrade from workflow-only installation
- Various file types (text, PDF, images)
- Large files / slow OCR
- Permission denied scenarios

## Timeline Considerations

This plan focuses on what needs to be built, not when. Key dependencies:

1. **CatboardCore framework** - must be complete before extension
2. **Signing setup** - required before any testing on real hardware
3. **Container app** - simple but required for extension to work
4. **Extension** - main deliverable, depends on framework
5. **Installer integration** - final step

## Open Questions

1. **Multiple file selection**: Should we support copying multiple files? Current Rust CLI does, but UX for notifications is unclear.

2. **Progress indication**: Long OCR operations have no feedback. Consider adding a progress HUD or menu bar indicator.

3. **Preferences**: Should the app have preferences (OCR language, notification sounds, etc.)?

4. **CLI coexistence**: Keep Rust CLI separate, or rewrite in Swift and have single codebase?
