import XCTest
@testable import CatboardCore

final class CatboardCoreTests: XCTestCase {

    // MARK: - FileReader Tests

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
        let url = URL(fileURLWithPath: "/nonexistent/path/to/file.txt")
        XCTAssertThrowsError(try FileReader.readContents(of: url)) { error in
            guard case CatboardError.fileNotFound = error else {
                XCTFail("Expected fileNotFound error, got \(error)")
                return
            }
        }
    }

    func testRejectsDirectory() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
        XCTAssertThrowsError(try FileReader.readContents(of: url)) { error in
            guard case CatboardError.isDirectory = error else {
                XCTFail("Expected isDirectory error, got \(error)")
                return
            }
        }
    }

    // MARK: - Happy Path: File Reading

    func testReadUTF8TextFile() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("catboard-test-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let expected = "Hello, catboard!\nLine 2\n"
        try expected.write(to: tempURL, atomically: true, encoding: .utf8)

        let content = try FileReader.readContents(of: tempURL)
        XCTAssertEqual(content, expected)
    }

    func testReadEmptyFile() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("catboard-test-empty-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try Data().write(to: tempURL)

        let content = try FileReader.readContents(of: tempURL)
        XCTAssertEqual(content, "")
    }

    func testRejectsBinaryFile() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("catboard-test-binary-\(UUID().uuidString).dat")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Write data with null bytes in the first 8KB
        var data = Data(repeating: 0x41, count: 100) // 'A' bytes
        data[50] = 0x00 // null byte
        try data.write(to: tempURL)

        XCTAssertThrowsError(try FileReader.readContents(of: tempURL)) { error in
            guard case CatboardError.binaryFile = error else {
                XCTFail("Expected binaryFile error, got \(error)")
                return
            }
        }
    }

    func testReadFileToClipboardEndToEnd() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("catboard-test-e2e-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let expected = "End-to-end test content for clipboard"
        try expected.write(to: tempURL, atomically: true, encoding: .utf8)

        // Step 1: Read file (the "slurp")
        let content = try FileReader.readContents(of: tempURL)
        XCTAssertEqual(content, expected)

        // Step 2: Copy to clipboard
        let expectation = self.expectation(description: "Copy completion")
        Clipboard.copy(content) { success in
            XCTAssertTrue(success)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)

        // Verify clipboard has the file contents
        let retrieved = Clipboard.getText()
        XCTAssertEqual(retrieved, expected)
    }

    // MARK: - CatboardError Tests

    func testErrorDescriptions() {
        let url = URL(fileURLWithPath: "/test/file.txt")

        XCTAssertNotNil(CatboardError.fileNotFound(url).errorDescription)
        XCTAssertNotNil(CatboardError.permissionDenied(url).errorDescription)
        XCTAssertNotNil(CatboardError.binaryFile(url).errorDescription)
        XCTAssertNotNil(CatboardError.fileTooLarge(url, 100_000_000).errorDescription)
        XCTAssertNotNil(CatboardError.outputTooLarge(200_000_000).errorDescription)
        XCTAssertNotNil(CatboardError.imageTooLarge(url, 10000, 10000).errorDescription)
        XCTAssertNotNil(CatboardError.isDirectory(url).errorDescription)
        XCTAssertNotNil(CatboardError.notFileURL(url).errorDescription)
        XCTAssertNotNil(CatboardError.extractionFailed(url, "Test error").errorDescription)
        XCTAssertNotNil(CatboardError.ocrTimeout(url).errorDescription)
    }

    // MARK: - Clipboard Tests

    func testClipboardCopyAndRetrieve() {
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
}
