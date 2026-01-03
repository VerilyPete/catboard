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

    guard let colorSpace = CGColorSpaceCreateDeviceRGB() else {
        return nil
    }

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
    if pdfDocument.isEncrypted && !pdfDocument.isLocked {
        // Encrypted but we can read it (no password required)
    } else if pdfDocument.isLocked {
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

    // Output all recognized text
    for line in allText {
        print(line)
    }

    // Return non-zero if any pages failed
    if pageErrors > 0 {
        fputs("Warning: \(pageErrors) of \(pageCount) pages had errors\n", stderr)
        return 1
    }

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

#### Error Handling Strategy
- **Page access failures**: Log warning to stderr, continue processing other pages
- **Render failures**: Log warning to stderr, continue processing other pages
- **OCR failures**: Log warning with error details to stderr, continue processing
- **Return code**: Return 1 if ANY page fails, so Rust knows there were issues
- **Partial results**: Always output successfully processed pages even if some fail

#### Password-Protected PDFs
- Check `pdfDocument.isLocked` before processing
- Return clear error message if PDF requires password
- Exit with code 1 (Rust will see extraction failed)

#### DPI Selection
- **150 DPI**: Good balance of OCR accuracy and memory usage
- A4 page at 150 DPI ≈ 1.2 MB per page image
- Future enhancement: Make configurable via CLI flag

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
- `tests/password-protected.pdf` - Password-protected PDF (for error handling test)

### Test Cases

| Test Case | Expected Behavior |
|-----------|-------------------|
| Multi-page scanned PDF | All pages OCR'd with separators |
| Single-page scanned PDF | Works same as before |
| Image files (PNG, JPG) | Backward compatible via NSImage |
| Empty PDF (0 pages) | Exit 1 with error message |
| Password-protected PDF | Exit 1 with clear error message |
| Corrupted page in middle | Log warning, continue, exit 1 |
| Rotated PDF | PDFKit handles rotation automatically |
| Very large PDF (100+ pages) | Sequential processing, ~1.2MB/page |

### Manual Testing
```bash
# Build
cd swift/catboard-ocr && swift build -c release

# Test multi-page PDF
.build/release/catboard-ocr /path/to/multi-page.pdf

# Test password-protected PDF (should fail with clear message)
.build/release/catboard-ocr /path/to/password-protected.pdf

# Test image (backward compatibility)
.build/release/catboard-ocr /path/to/image.png

# Full integration
cargo build && ./target/debug/catboard tests/multi-page.pdf
```

### Integration Test (Rust)
```rust
#[test]
fn test_multi_page_pdf_ocr_integration() {
    let result = read_file_contents("tests/multi-page-scanned.pdf");
    assert!(result.is_ok());
    let text = result.unwrap();
    assert!(text.contains("--- Page 2 ---")); // Verify separator
}
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

This should be documented in release notes.

## Memory Considerations

- A4 page at 150 DPI: ~1.2 MB per page image
- 100-page PDF: ~120 MB peak memory (sequential processing)
- Pages are processed one at a time (not loaded all at once)
- Very large PDFs (500+ pages): ~600 MB, may be slow but safe

## Implementation Checklist

### Core Implementation
- [ ] Update `Package.swift` to link Quartz framework
- [ ] Add `import Quartz` to main.swift
- [ ] Implement `isPDFFile()` function
- [ ] Implement `renderPDFPage()` function with colorspace safety
- [ ] Implement `performPDFOCR()` function
- [ ] Refactor `performOCR()` to route PDF vs image
- [ ] Rename existing OCR function to `performImageOCR()`
- [ ] Add page separators for multi-page output

### Error Handling
- [ ] Add password-protected PDF detection with clear error
- [ ] Log page access failures to stderr (don't silently skip)
- [ ] Log page render failures to stderr
- [ ] Log OCR failures with error details to stderr
- [ ] Return exit code 1 if any page fails
- [ ] Handle empty PDF (0 pages) case

### Testing
- [ ] Create multi-page test PDF (3+ pages)
- [ ] Create password-protected test PDF
- [ ] Test with existing rotated PDF (`tests/2025-12-12_12-11-14.pdf`)
- [ ] Add Rust integration test for multi-page output
- [ ] Test backward compatibility with image files

### Documentation
- [ ] Update Rust code comments in `src/file.rs`
- [ ] Update README with multi-page PDF support
- [ ] Document output format change in release notes

## Future Enhancements (Out of Scope)

- Configurable DPI via CLI flag (`--dpi 200`)
- Parallel page processing for performance
- Page range selection (`--pages 1-5`)
- Progress reporting for large documents
- Language/charset configuration
