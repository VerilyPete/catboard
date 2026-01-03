# Multi-Page PDF OCR Implementation Plan

## Overview

Currently, catboard's OCR helper (`catboard-ocr`) uses `NSImage` to load files for OCR processing. While this works well for images and single-page PDFs, `NSImage` only renders the first page of multi-page PDFs. This limitation means that scanned multi-page documents only have their first page extracted.

This plan details how to add PDFKit support to `catboard-ocr` to iterate through all pages of a PDF, render each page to a `CGImage`, run OCR on each, and concatenate the results.

## Current Architecture

### Swift Helper (catboard-ocr)
- **Location**: `swift/catboard-ocr/Sources/main.swift`
- **Function**: `performOCR(on imageURL: URL)` loads file with `NSImage`, converts to `CGImage`, runs `VNRecognizeTextRequest`
- **Limitation**: Uses `NSImage(contentsOf:)` which only renders PDF page 1

### Rust Integration
- **Location**: `src/file.rs`, function `extract_pdf_with_ocr`
- **Behavior**: Passes PDF path directly to OCR helper

## Implementation Steps

### Step 1: Update Package.swift

Add Quartz framework dependency (contains PDFKit):

```swift
// swift/catboard-ocr/Package.swift
let package = Package(
    name: "catboard-ocr",
    platforms: [
        .macOS(.v10_15)
    ],
    targets: [
        .executableTarget(
            name: "catboard-ocr",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("Quartz")
            ]
        )
    ]
)
```

### Step 2: Refactor main.swift

Key changes to the Swift OCR helper:

```swift
import Foundation
import Vision
import AppKit
import Quartz  // PDFKit is part of Quartz

let PDF_RENDER_DPI: CGFloat = 150.0

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

    // White background
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
        return 1
    }

    var allText: [String] = []

    for pageIndex in 0..<pdfDocument.pageCount {
        guard let page = pdfDocument.page(at: pageIndex),
              let cgImage = renderPDFPage(page) else { continue }

        if let pageText = try? recognizeText(in: cgImage) {
            if pageIndex > 0 && !allText.isEmpty {
                allText.append("")
                allText.append("--- Page \(pageIndex + 1) ---")
                allText.append("")
            }
            allText.append(contentsOf: pageText)
        }
    }

    for line in allText { print(line) }
    return 0
}

/// Main entry point - routes to PDF or image handler
func performOCR(on fileURL: URL) -> Int32 {
    if isPDFFile(fileURL) {
        return performPDFOCR(on: fileURL)
    } else {
        return performImageOCR(on: fileURL)  // Existing NSImage-based logic
    }
}
```

### Step 3: Key Implementation Details

#### DPI Selection
- **150 DPI**: Good balance of OCR accuracy and memory usage
- A4 page at 150 DPI ≈ 1.2 MB per page image

#### Page Separators
Multi-page output format:
```
[Page 1 text]

--- Page 2 ---

[Page 2 text]
```

#### Rotation Handling
PDFKit's `PDFPage.draw(with:to:)` automatically handles page rotation metadata.

## Testing Strategy

### Test Files Needed
- `tests/single-page-scanned.pdf` - One page scanned document
- `tests/multi-page-scanned.pdf` - 3+ page scanned document

### Manual Testing
```bash
# Build
cd swift/catboard-ocr && swift build -c release

# Test multi-page PDF
.build/release/catboard-ocr /path/to/multi-page.pdf

# Test image (backward compatibility)
.build/release/catboard-ocr /path/to/image.png

# Full integration
cargo build && ./target/debug/catboard tests/multi-page.pdf
```

## Breaking Changes

**None expected.** The implementation is backward compatible:
- Image files continue to work via NSImage path
- Single-page PDFs work the same way
- Multi-page PDFs now return all pages (enhancement)

### Output Format Change
For multi-page PDFs:
- **Before**: Only first page text
- **After**: All pages with `--- Page N ---` separators

## Memory Considerations

- A4 page at 150 DPI: ~1.2 MB per page image
- 100-page PDF: ~120 MB peak memory
- Pages are processed sequentially (not loaded all at once)

## Implementation Checklist

- [ ] Update `Package.swift` to link Quartz framework
- [ ] Add `import Quartz` to main.swift
- [ ] Implement `isPDFFile()` function
- [ ] Implement `renderPDFPage()` function
- [ ] Implement `performPDFOCR()` function
- [ ] Refactor `performOCR()` to route PDF vs image
- [ ] Rename existing OCR function to `performImageOCR()`
- [ ] Add page separators for multi-page output
- [ ] Update Rust code comments in `src/file.rs`
- [ ] Create multi-page test PDF
- [ ] Test with existing rotated PDF (`tests/2025-12-12_12-11-14.pdf`)
- [ ] Update README with multi-page PDF support
