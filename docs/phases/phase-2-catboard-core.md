# Phase 2: CatboardCore Framework

**Goal:** Implement the shared framework with all file processing logic.

**Dependencies:** Phase 1 (Xcode project must exist)

**Reference:** [finder-extension-plan.md](../finder-extension-plan.md)

---

## Table of Contents

| File | Purpose | Lines |
|------|---------|-------|
| `CatboardCore/Logging.swift` | OSLog extension with logging categories | ~15 |
| `CatboardCore/CatboardError.swift` | Error enum with localized descriptions | ~50 |
| `CatboardCore/FileReader.swift` | Main entry point, file type routing, text reading | ~150 |
| `CatboardCore/PDFExtractor.swift` | PDFKit text extraction with OCR fallback | ~40 |
| `CatboardCore/OCREngine.swift` | Vision framework OCR with timeout | ~270 |
| `CatboardCore/Clipboard.swift` | Thread-safe NSPasteboard wrapper | ~50 |

**Total:** ~575 lines

---

## File 1: Logging.swift

**Purpose:** Centralized logging with categories for debugging.

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

---

## File 2: CatboardError.swift

**Purpose:** Typed errors with user-friendly descriptions.

```swift
import Foundation

public enum CatboardError: LocalizedError {
    case fileNotFound(URL)
    case permissionDenied(URL)
    case binaryFile(URL)
    case fileTooLarge(URL, Int64)
    case outputTooLarge(Int)
    case imageTooLarge(URL, Int, Int)
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
        case .imageTooLarge(let url, let width, let height):
            let mpx = (width * height) / 1_000_000
            return "Image too large (\(mpx)MP): \(url.lastPathComponent)"
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

---

## File 3: FileReader.swift

**Purpose:** Main entry point for reading file contents. Routes to appropriate handler based on file type.

**Key behaviors:**
- Validates file URL (must be local file, not directory, readable, within size limit)
- Handles broken symlinks
- Uses UTType for file type detection with extension fallback
- Routes to PDFExtractor, OCREngine, or text reading
- Detects binary files by checking for null bytes
- Supports multiple text encodings (UTF-8, UTF-16, Latin-1, etc.)

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

---

## File 4: PDFExtractor.swift

**Purpose:** Extract text from PDFs using PDFKit, with OCR fallback for scanned documents.

**Key behaviors:**
- Opens PDF with PDFKit
- Checks for password protection
- Extracts embedded text from all pages
- Falls back to OCR if no text found (scanned PDF)

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

---

## File 5: OCREngine.swift

**Purpose:** Perform OCR using Vision framework on images and PDF pages.

**Key behaviors:**
- Renders PDF pages at 150 DPI for OCR
- Validates image dimensions (50MP limit)
- 60-second timeout per OCR operation
- Uses autoreleasepool for memory management
- Adds page separators for multi-page PDFs
- Reports failed pages as warnings

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

    /// Maximum image size in pixels (50 megapixels)
    private static let maxImagePixels = 50_000_000

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

        // Validate image dimensions to prevent memory exhaustion
        let pixels = cgImage.width * cgImage.height
        if pixels > maxImagePixels {
            throw CatboardError.imageTooLarge(url, cgImage.width, cgImage.height)
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

        // Validate page dimensions to prevent memory exhaustion
        if width * height > maxImagePixels {
            os_log("Page dimensions too large: %dx%d (%d pixels)", log: .ocr, type: .error, width, height, width * height)
            return nil
        }

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

---

## File 6: Clipboard.swift

**Purpose:** Thread-safe clipboard access with size limits.

**Key behaviors:**
- All NSPasteboard access on main thread
- Async copy with completion handler
- Sync copy for main thread callers
- Output size validation (100MB limit)

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

---

## Success Criteria

1. Framework builds without errors
2. All 6 Swift files compile
3. Public API is accessible: `FileReader.readContents(of:)`, `Clipboard.copy(_:completion:)`
4. Can test with a simple command-line harness:
   ```swift
   let text = try FileReader.readContents(of: URL(fileURLWithPath: "/path/to/test.txt"))
   print(text)
   ```

---

## Do NOT

- Modify FinderSync.swift (Phase 3)
- Modify AppDelegate.swift (Phase 4)
- Add unit test targets (can be added later)
- Configure code signing (Phase 5)
