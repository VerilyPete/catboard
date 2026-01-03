import Foundation
import Vision
import AppKit
import Quartz  // PDFKit is part of Quartz

/// Simple OCR CLI using macOS Vision framework
/// Usage: catboard-ocr <file-path>
/// Outputs recognized text to stdout, one line per text block
/// Supports images (PNG, JPG, etc.) and multi-page PDFs

let PDF_RENDER_DPI: CGFloat = 150.0

func printUsage() {
    fputs("Usage: catboard-ocr <file-path>\n", stderr)
    fputs("Extracts text from an image or PDF using macOS Vision OCR.\n", stderr)
}

/// Check if a file is a PDF based on extension
func isPDFFile(_ url: URL) -> Bool {
    return url.pathExtension.lowercased() == "pdf"
}

/// Perform OCR on a single CGImage
func recognizeText(in cgImage: CGImage) throws -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try handler.perform([request])

    return request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
}

/// Render a PDF page to CGImage at specified DPI
func renderPDFPage(_ page: PDFPage, dpi: CGFloat = PDF_RENDER_DPI) -> CGImage? {
    let pageRect = page.bounds(for: .mediaBox)
    let scale = dpi / 72.0
    let width = Int(pageRect.width * scale)
    let height = Int(pageRect.height * scale)

    // CGColorSpaceCreateDeviceRGB() always returns a valid colorspace
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // White background (important for scanned documents)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    context.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: context)

    return context.makeImage()
}

/// Perform OCR on a multi-page PDF
func performPDFOCR(on pdfURL: URL) -> Int32 {
    guard let pdfDocument = PDFDocument(url: pdfURL) else {
        fputs("Error: Could not open PDF: \(pdfURL.path)\n", stderr)
        fputs("The file may be corrupted or inaccessible.\n", stderr)
        return 1
    }

    // Check for password protection
    if pdfDocument.isLocked {
        fputs("Error: PDF is password-protected\n", stderr)
        return 1
    }

    let pageCount = pdfDocument.pageCount
    if pageCount == 0 {
        fputs("Error: PDF has no pages\n", stderr)
        return 1
    }

    var allText: [String] = []
    var pageErrors = 0

    for pageIndex in 0..<pageCount {
        // Access page with error logging
        guard let page = pdfDocument.page(at: pageIndex) else {
            fputs("Warning: Could not access page \(pageIndex + 1)\n", stderr)
            pageErrors += 1
            continue
        }

        // Render page with error logging
        guard let cgImage = renderPDFPage(page) else {
            fputs("Warning: Could not render page \(pageIndex + 1)\n", stderr)
            pageErrors += 1
            continue
        }

        // OCR with error logging
        do {
            let pageText = try recognizeText(in: cgImage)

            // Add page separator for multi-page documents (not before first page)
            if pageIndex > 0 && !allText.isEmpty {
                allText.append("")
                allText.append("--- Page \(pageIndex + 1) ---")
                allText.append("")
            }

            allText.append(contentsOf: pageText)
        } catch {
            fputs("Warning: OCR failed on page \(pageIndex + 1): \(error.localizedDescription)\n", stderr)
            pageErrors += 1
            continue
        }
    }

    // Check if we got any text at all
    let combinedText = allText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    if combinedText.isEmpty && pageErrors == 0 {
        fputs("Error: No text recognized in PDF (all pages were blank or unreadable)\n", stderr)
        return 1
    }

    // Output all recognized text
    for line in allText {
        print(line)
    }

    // Return non-zero if any pages failed
    if pageErrors > 0 {
        fputs("Error: \(pageErrors) of \(pageCount) pages had errors\n", stderr)
        return 1
    }

    return 0
}

/// Perform OCR on an image file using NSImage
func performImageOCR(on imageURL: URL) -> Int32 {
    guard let image = NSImage(contentsOf: imageURL) else {
        fputs("Error: Could not load image: \(imageURL.path)\n", stderr)
        return 1
    }

    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fputs("Error: Could not convert image to CGImage\n", stderr)
        return 1
    }

    do {
        let lines = try recognizeText(in: cgImage)
        for line in lines {
            print(line)
        }
        return 0
    } catch {
        fputs("Error: OCR failed: \(error.localizedDescription)\n", stderr)
        return 1
    }
}

/// Main entry point - routes to PDF or image handler
func performOCR(on fileURL: URL) -> Int32 {
    if isPDFFile(fileURL) {
        return performPDFOCR(on: fileURL)
    } else {
        return performImageOCR(on: fileURL)
    }
}

// Main
guard CommandLine.arguments.count == 2 else {
    printUsage()
    exit(1)
}

let filePath = CommandLine.arguments[1]

if filePath == "--help" || filePath == "-h" {
    printUsage()
    exit(0)
}

let fileURL = URL(fileURLWithPath: filePath)

guard FileManager.default.fileExists(atPath: filePath) else {
    fputs("Error: File not found: \(filePath)\n", stderr)
    exit(1)
}

exit(performOCR(on: fileURL))
