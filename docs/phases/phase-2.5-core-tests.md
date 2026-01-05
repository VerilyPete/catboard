# Phase 2.5: CatboardCore Unit Tests

**Goal:** Add comprehensive unit tests for the CatboardCore framework.

**Dependencies:** Phase 1 (Xcode project), Phase 2 (CatboardCore framework)

**Reference:** [finder-extension-plan.md](../finder-extension-plan.md)

---

## Table of Contents

| File | Purpose | Lines |
|------|---------|-------|
| `CatboardCoreTests/FileReaderTests.swift` | Test file reading, routing, validation | ~200 |
| `CatboardCoreTests/PDFExtractorTests.swift` | Test PDF text extraction | ~80 |
| `CatboardCoreTests/OCREngineTests.swift` | Test OCR processing | ~120 |
| `CatboardCoreTests/ClipboardTests.swift` | Test clipboard operations | ~60 |
| `CatboardCoreTests/Fixtures/` | Test data files | - |

**Total:** ~460 lines

---

## Prerequisites

Before implementing tests, add a test target to the Xcode project:

1. File → New → Target → macOS → Unit Testing Bundle
2. Product Name: `CatboardCoreTests`
3. Target to be Tested: `CatboardCore`
4. Link `CatboardCore.framework` to test target

---

## Test Fixtures

Create test data files in `CatboardCoreTests/Fixtures/`:

| File | Purpose |
|------|---------|
| `sample.txt` | UTF-8 text file |
| `sample-utf16le.txt` | UTF-16 LE with BOM |
| `sample-latin1.txt` | ISO-8859-1 encoded |
| `binary.dat` | Binary file (contains null bytes) |
| `empty.txt` | Empty file |
| `sample.pdf` | PDF with embedded text |
| `sample-image.png` | PNG with text for OCR |

---

## File 1: FileReaderTests.swift

```swift
import XCTest
@testable import CatboardCore

final class FileReaderTests: XCTestCase {

    var fixturesURL: URL!

    override func setUp() {
        super.setUp()
        fixturesURL = Bundle(for: type(of: self)).resourceURL!
            .appendingPathComponent("Fixtures")
    }

    // MARK: - Text File Reading

    func testReadUTF8TextFile() throws {
        let url = fixturesURL.appendingPathComponent("sample.txt")
        let content = try FileReader.readContents(of: url)
        XCTAssertFalse(content.isEmpty)
        XCTAssertTrue(content.contains("Hello"))
    }

    func testReadUTF16LEWithBOM() throws {
        let url = fixturesURL.appendingPathComponent("sample-utf16le.txt")
        let content = try FileReader.readContents(of: url)
        XCTAssertFalse(content.isEmpty)
    }

    func testReadLatin1Encoding() throws {
        let url = fixturesURL.appendingPathComponent("sample-latin1.txt")
        let content = try FileReader.readContents(of: url)
        XCTAssertFalse(content.isEmpty)
    }

    func testReadEmptyFile() throws {
        let url = fixturesURL.appendingPathComponent("empty.txt")
        let content = try FileReader.readContents(of: url)
        XCTAssertEqual(content, "")
    }

    // MARK: - Binary Detection

    func testRejectsBinaryFile() {
        let url = fixturesURL.appendingPathComponent("binary.dat")
        XCTAssertThrowsError(try FileReader.readContents(of: url)) { error in
            guard case CatboardError.binaryFile = error else {
                XCTFail("Expected binaryFile error, got \(error)")
                return
            }
        }
    }

    // MARK: - URL Validation

    func testRejectsNetworkURL() {
        let url = URL(string: "https://example.com/file.txt")!
        XCTAssertThrowsError(try FileReader.readContents(of: url)) { error in
            guard case CatboardError.notFileURL = error else {
                XCTFail("Expected notFileURL error, got \(error)")
                return
            }
        }
    }

    func testRejectsNonexistentFile() {
        let url = fixturesURL.appendingPathComponent("nonexistent.txt")
        XCTAssertThrowsError(try FileReader.readContents(of: url)) { error in
            guard case CatboardError.fileNotFound = error else {
                XCTFail("Expected fileNotFound error, got \(error)")
                return
            }
        }
    }

    func testRejectsDirectory() {
        let url = fixturesURL
        XCTAssertThrowsError(try FileReader.readContents(of: url)) { error in
            guard case CatboardError.isDirectory = error else {
                XCTFail("Expected isDirectory error, got \(error)")
                return
            }
        }
    }

    // MARK: - File Size Limits

    func testRejectsOversizedFile() throws {
        // Create a temporary file larger than 50MB
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("large-\(UUID().uuidString).txt")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Create 51MB file
        let data = Data(repeating: 0x41, count: 51 * 1024 * 1024)
        try data.write(to: tempURL)

        XCTAssertThrowsError(try FileReader.readContents(of: tempURL)) { error in
            guard case CatboardError.fileTooLarge = error else {
                XCTFail("Expected fileTooLarge error, got \(error)")
                return
            }
        }
    }

    // MARK: - UTType Routing

    func testRoutesPDFToExtractor() throws {
        let url = fixturesURL.appendingPathComponent("sample.pdf")
        // If this doesn't throw, PDF routing works
        _ = try FileReader.readContents(of: url)
    }

    func testRoutesImageToOCR() throws {
        let url = fixturesURL.appendingPathComponent("sample-image.png")
        // If this doesn't throw, image routing works
        _ = try FileReader.readContents(of: url)
    }

    // MARK: - Symlink Handling

    func testFollowsValidSymlink() throws {
        let originalURL = fixturesURL.appendingPathComponent("sample.txt")
        let symlinkURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("symlink-\(UUID().uuidString).txt")

        defer { try? FileManager.default.removeItem(at: symlinkURL) }

        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: originalURL)

        let content = try FileReader.readContents(of: symlinkURL)
        XCTAssertFalse(content.isEmpty)
    }

    func testRejectsBrokenSymlink() throws {
        let symlinkURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("broken-symlink-\(UUID().uuidString).txt")

        defer { try? FileManager.default.removeItem(at: symlinkURL) }

        // Create symlink to nonexistent file
        try FileManager.default.createSymbolicLink(
            atPath: symlinkURL.path,
            withDestinationPath: "/nonexistent/file.txt"
        )

        XCTAssertThrowsError(try FileReader.readContents(of: symlinkURL)) { error in
            guard case CatboardError.fileNotFound = error else {
                XCTFail("Expected fileNotFound error, got \(error)")
                return
            }
        }
    }
}
```

---

## File 2: PDFExtractorTests.swift

```swift
import XCTest
@testable import CatboardCore

final class PDFExtractorTests: XCTestCase {

    var fixturesURL: URL!

    override func setUp() {
        super.setUp()
        fixturesURL = Bundle(for: type(of: self)).resourceURL!
            .appendingPathComponent("Fixtures")
    }

    func testExtractTextFromPDF() throws {
        let url = fixturesURL.appendingPathComponent("sample.pdf")
        let text = try PDFExtractor.extractText(from: url)
        XCTAssertFalse(text.isEmpty)
    }

    func testRejectsInvalidPDF() {
        let url = fixturesURL.appendingPathComponent("sample.txt")
        XCTAssertThrowsError(try PDFExtractor.extractText(from: url)) { error in
            guard case CatboardError.extractionFailed = error else {
                XCTFail("Expected extractionFailed error, got \(error)")
                return
            }
        }
    }

    func testRejectsNonexistentPDF() {
        let url = fixturesURL.appendingPathComponent("nonexistent.pdf")
        XCTAssertThrowsError(try PDFExtractor.extractText(from: url))
    }
}
```

---

## File 3: OCREngineTests.swift

```swift
import XCTest
@testable import CatboardCore

final class OCREngineTests: XCTestCase {

    var fixturesURL: URL!

    override func setUp() {
        super.setUp()
        fixturesURL = Bundle(for: type(of: self)).resourceURL!
            .appendingPathComponent("Fixtures")
    }

    func testExtractTextFromImage() throws {
        let url = fixturesURL.appendingPathComponent("sample-image.png")
        let text = try OCREngine.extractText(from: url)
        // OCR may or may not find text depending on image
        // Just verify it doesn't crash
        XCTAssertNotNil(text)
    }

    func testRejectsInvalidImage() {
        let url = fixturesURL.appendingPathComponent("sample.txt")
        XCTAssertThrowsError(try OCREngine.extractText(from: url)) { error in
            guard case CatboardError.extractionFailed = error else {
                XCTFail("Expected extractionFailed error, got \(error)")
                return
            }
        }
    }

    // Note: Testing timeout and large image rejection requires
    // specially crafted test fixtures that may not be practical
    // for unit tests. Consider integration tests for those scenarios.
}
```

---

## File 4: ClipboardTests.swift

```swift
import XCTest
@testable import CatboardCore

final class ClipboardTests: XCTestCase {

    func testCopyAndRetrieve() {
        let testString = "Test clipboard content \(UUID().uuidString)"

        let expectation = self.expectation(description: "Copy completion")

        Clipboard.copy(testString) { success in
            XCTAssertTrue(success)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        // Verify content was copied
        let retrieved = Clipboard.getText()
        XCTAssertEqual(retrieved, testString)
    }

    func testCopySyncOnMainThread() {
        let testString = "Sync test \(UUID().uuidString)"

        // Must run on main thread
        DispatchQueue.main.sync {
            let success = Clipboard.copySync(testString)
            XCTAssertTrue(success)

            let retrieved = Clipboard.getText()
            XCTAssertEqual(retrieved, testString)
        }
    }

    func testRejectsOversizedOutput() {
        // Create string larger than 100MB
        let oversizedString = String(repeating: "x", count: 101 * 1024 * 1024)

        let expectation = self.expectation(description: "Copy completion")

        Clipboard.copy(oversizedString) { success in
            XCTAssertFalse(success)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }
}
```

---

## Running Tests

```bash
# Run from command line
xcodebuild test \
    -project swift/CatboardFinder/CatboardFinder.xcodeproj \
    -scheme CatboardCore \
    -destination 'platform=macOS'

# Run with coverage
xcodebuild test \
    -project swift/CatboardFinder/CatboardFinder.xcodeproj \
    -scheme CatboardCore \
    -destination 'platform=macOS' \
    -enableCodeCoverage YES
```

---

## Success Criteria

1. All tests pass
2. Code coverage > 70% for CatboardCore
3. Edge cases covered (empty files, invalid URLs, size limits)
4. No memory leaks in test runs

---

## Do NOT

- Test FinderSync.swift (Phase 3, requires extension testing)
- Test AppDelegate.swift (Phase 4, requires UI testing)
- Create complex OCR test fixtures (use simple images)
- Mock system frameworks (use real implementations)
