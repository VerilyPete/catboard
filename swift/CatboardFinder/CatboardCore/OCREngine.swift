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
