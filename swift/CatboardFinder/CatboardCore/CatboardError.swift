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
