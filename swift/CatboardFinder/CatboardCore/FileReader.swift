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
